//
//  ContentView.swift
//  APIBibleTest-2
//
//  Created by Xcode Developer on 2/1/26.
//

import SwiftUI
import Observation
import FoundationModels

// Psalm data model

struct PsalmsBook: Decodable {
    let book: Book
}

struct Book: Decodable {
    let title: String
    let chapters: [Chapter]
}

struct Chapter: Decodable {
    let chapter: Int
    let verses: [Verse]
}

// Parsed request struct

struct PsalmQuery {
    let chapter: Int
    let range: String?
}

enum PromptParser {
    
    static func parseAll(_ input: String) -> [PsalmQuery] {
        let pattern = #"\bpsalm\s+(\d+)(?:\s*:\s*(\d+(?:-\d+)?))?"#
        
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        
        guard let matches = regex?.matches(in: input, options: [], range: range) else {
            return []
        }
        
        return matches.compactMap { match in
            guard
                let chapterRange = Range(match.range(at: 1), in: input)
            else { return nil }
            let chapter = Int(input[chapterRange])!
            let verseRange = Range(match.range(at: 2), in: input)
            let verses = verseRange.map {
                input[$0]
                    .replacingOccurrences(of: "to", with: "-")
                    .replacingOccurrences(of: "through", with: "-")
                    .replacingOccurrences(of: " ", with: "")
            }
            return PsalmQuery(chapter: chapter, range: verses)
        }
    }
}

enum AIPromptNormalizer {

    static let instruction = """
    You format user prompts for chapters and verses ranges in Psalms and/or Proverbs into valid biblical references.
    For example: if the user enters "The first verse of every psalm in Psalms," or, "The first verse of every chapter in Proverbs," you would convert that to:
    
    Psalm 1:1, Psalm 2:1, Psalm 3:1...Psalm 150:1 (the ellipses are a substitute for Psalm 4 through 149)

    Convert the user's request into a comma-separated list of Psalm references.
    Each reference must use one of these formats:

    Valid formats include:

    - **Entire book:** `Proverbs` or `Book of Proverbs`
    - **Chapter range:** `Proverbs 1-3`
    - **Single chapter:** `Proverbs 16`
    - **Verse range:** `Proverbs 16:1-9`
    - **Multiple ranges:** `Proverbs 3:5-6, 16:9, 19:21`
    
    Rules:
    - Expand ordinal language (e.g. "first verse" → verse 1)
    - Expand ranges (e.g. "first three psalms" → Psalm 1, Psalm 2, Psalm 3)
    - If a verse is specified, ALWAYS include it
    - If no verse is specified, return the whole chapter
    - Return ONLY the normalized string, no commentary
    
    Important:
    Make every attempt to interpret the user prompt, whether it conforms to expectations or otherwise.
    """

    static func normalize(_ input: String) async throws -> String {
        let session = LanguageModelSession()

        let prompt = """
        \(instruction)

        User request:
        \(input)
        """

        let response = try await session.respond(to: prompt)

        let cleaned = response.content
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return cleaned
    }
}

// PsalmService

struct Verse: Decodable {
    let verse: Int
    let text: String
}

enum PsalmService {
    
    static func loadVerses(
        chapterNumber: Int,
        verseRange: String?
    ) throws -> [Verse] {
        
        guard let url = Bundle.main.url(
            forResource: "Psalms_KJV_structured_title_chapters",
            withExtension: "txt"
        ) else {
            throw NSError(domain: "PsalmService", code: 1)
        }
        
        let data = try Data(contentsOf: url)
        let psalms = try JSONDecoder().decode(PsalmsBook.self, from: data)
        
        guard let chapter = psalms.book.chapters.first(
            where: { $0.chapter == chapterNumber }
        ) else {
            return []
        }
        
        let (start, end) = verseRange.map(parseRange) ?? (1, Int.max)
        
        return chapter.verses
            .filter { verse in
                verse.verse != 0 && verse.verse >= start && verse.verse <= end
            }
            .sorted { $0.verse < $1.verse }
    }
    
    private static func parseRange(_ input: String) -> (Int, Int) {
        let parts = input.split(separator: "-").compactMap { Int($0) }
        if parts.count == 2 {
            return (parts[0], parts[1])
        } else if parts.count == 1 {
            return (parts[0], parts[0])
        } else {
            return (1, Int.max)
        }
    }
}

// Results display model
struct DisplayVerse: Identifiable {
    let id = UUID()
    let chapter: Int
    let verse: Int
    let text: String
}

// Interface

struct ContentView: View {
    @State private var psalm = ""
    @State private var range = ""
    @State private var prompt = ""
    @State private var verses: [DisplayVerse] = []
    @State private var error: String?
    @State private var isLoading = false
    enum FocusField {
        case prompt
    }
    @FocusState private var focusedField: FocusField?
    
    var body: some View {
        VStack(spacing: 12) {
            
            TextField("e.g. Psalm 23:1-6 or 'Psalm 23 verses 1 through 6'", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .prompt)
                .onSubmit {
                    load()
                }
            
            Button("Load Verses") {
                focusedField = nil
                load()
            }
            .disabled(isLoading)
            .buttonStyle(.borderedProminent)
            
            if let error {
                Text(error).foregroundColor(.red)
            }

            List(verses) { verse in
                Text("Psalm \(verse.chapter):\(verse.verse) \(verse.text)")
            }
        }
        .padding()
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .prompt
            }
        }
    }
    
    private func load() {
        guard !isLoading else { return }
        isLoading = true

        error = nil
        verses = []

        Task {
            defer { isLoading = false }

            do {
                let aiOutput = try await AIPromptNormalizer.normalize(prompt)

                guard !aiOutput.isEmpty else {
                    error = "AI returned empty output"
                    return
                }

                let cleanedPrompt = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                print("AI normalized prompt:", cleanedPrompt)

                let queries = PromptParser.parseAll(cleanedPrompt)

                guard !queries.isEmpty else {
                    error = "Could not understand the reference."
                    return
                }

                for query in queries {
                    let result = try PsalmService.loadVerses(
                        chapterNumber: query.chapter,
                        verseRange: query.range
                    )

                    let displayVerses = result.map {
                        DisplayVerse(
                            chapter: query.chapter,
                            verse: $0.verse,
                            text: $0.text
                        )
                    }

                    verses.append(contentsOf: displayVerses)
                }

                if verses.isEmpty {
                    error = "No verses found"
                }

            } catch let thrownError {
                error = thrownError.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
}
