import Foundation
import Testing
@testable import Ghostty

/// Tests for `GroupNameGenerator` (`SPEC.md` §8, §19.1 "random group name
/// uniqueness"). Randomness is injected via a deterministic generator so the
/// tests are reproducible.
struct GroupNameGeneratorTests {
    /// A deterministic `RandomNumberGenerator` (SplitMix64) so generated names
    /// are reproducible across runs.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// All `adjective-noun` combinations from the word lists.
    private static var allCombinations: Set<String> {
        var result = Set<String>()
        for adjective in GroupNameGenerator.adjectives {
            for noun in GroupNameGenerator.nouns {
                result.insert("\(adjective)-\(noun)")
            }
        }
        return result
    }

    @Test func makeProducesAdjectiveNounFromWordLists() {
        var generator = SeededGenerator(seed: 1)
        let name = GroupNameGenerator.make(existing: [], using: &generator)

        let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
        #expect(parts.count == 2)
        #expect(GroupNameGenerator.adjectives.contains(parts[0]))
        #expect(GroupNameGenerator.nouns.contains(parts[1]))
    }

    @Test func makeNeverReturnsAnExistingName() {
        var generator = SeededGenerator(seed: 42)
        var existing: Set<String> = []

        // Accumulate generated names; each must be unique against what came
        // before, even as the small word lists fill up and force fallbacks.
        for _ in 0..<80 {
            let name = GroupNameGenerator.make(existing: existing, using: &generator)
            #expect(!existing.contains(name))
            existing.insert(name)
        }

        #expect(existing.count == 80)
    }

    @Test func makeFallsBackToNumberedNameWhenCombinationsExhausted() {
        let existing = Self.allCombinations
        var generator = SeededGenerator(seed: 7)

        let name = GroupNameGenerator.make(existing: existing, using: &generator)
        #expect(!existing.contains(name))
        #expect(name.hasPrefix("group-"))
    }

    @Test func fallbackWalksPastTakenNumberedNames() {
        // With all 100 combinations taken, the numbered fallback engages. Count
        // is then 100; pre-occupying "group-102" forces the first candidate
        // ("group-\(count + 1)" after the extra insert) to be taken, so a naive
        // implementation that returned it would collide. The result must still
        // be free.
        var existing = Self.allCombinations
        existing.insert("group-102")
        var generator = SeededGenerator(seed: 7)

        let name = GroupNameGenerator.make(existing: existing, using: &generator)
        #expect(!existing.contains(name))
        #expect(name.hasPrefix("group-"))
    }
}
