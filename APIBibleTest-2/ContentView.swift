//
//  ContentView.swift
//  APIBibleTest-2
//
//  Created by Xcode Developer on 2/1/26.
//

import SwiftUI
import Observation

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
        let pattern = #"\bpsalms?\s+(\d+)(?:\s*[:]\s*(\d+(?:\s*(?:-|to|through)\s*\d+)?))?"#
        
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
    
    var body: some View {
        VStack(spacing: 12) {
            
            TextField("e.g. Psalm 23:1-6 or 'Psalm 23 verses 1 through 6'", text: $prompt)
                .textFieldStyle(.roundedBorder)
            
            Button("Load Verses") {
                load()
            }
            .buttonStyle(.borderedProminent)
            
            if let error {
                Text(error).foregroundColor(.red)
            }

            List(verses) { verse in
                Text("Psalm \(verse.chapter):\(verse.verse) \(verse.text)")
            }
        }
        .padding()
    }
    
    private func load() {
        error = nil
        verses = []
        
        let queries = PromptParser.parseAll(prompt)
        
        guard !queries.isEmpty else {
            error = "Could not understand the reference."
            return
        }
        
        do {
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
        } catch {
            print("(One or more specified ranges were not found)", error)
        }
    }
}

#Preview {
    ContentView()
}
