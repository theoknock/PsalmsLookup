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

// PsalmService

struct Verse: Decodable {
    let verse: Int
    let text: String
}

enum PsalmService {

    static func loadVerses(
        chapterNumber: Int,
        verseRange: String
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

        let (start, end) = parseRange(verseRange)

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

// Interface

struct ContentView: View {
    @State private var psalm = ""
    @State private var range = ""
    @State private var verses: [Verse] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {

            TextField("Psalm (e.g. 23)", text: $psalm)
                .textFieldStyle(.roundedBorder)

            TextField("Verse range (e.g. 1-6 or 4)", text: $range)
                .textFieldStyle(.roundedBorder)

            Button("Load Verses") {
                load()
            }
            .buttonStyle(.borderedProminent)

            if let error {
                Text(error).foregroundColor(.red)
            }

            List(verses, id: \.verse) { verse in
                Text("\(verse.verse). \(verse.text)")
            }
        }
        .padding()
    }

    private func load() {
        error = nil
        verses = []

        guard let chapter = Int(psalm) else {
            error = "Invalid Psalm number"
            return
        }

        do {
            verses = try PsalmService.loadVerses(
                chapterNumber: chapter,
                verseRange: range
            )
            if verses.isEmpty {
                error = "No verses found"
            }
        } catch {
            print("(The specified range was not found: )", error)
        }
    }
}

#Preview {
    ContentView()
}
