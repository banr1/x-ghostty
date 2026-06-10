import Foundation

/// Generates random `adjective-noun` names for newly created groups
/// (`SPEC.md` §8).
///
/// Names are generated only at creation time and stored in `GroupState.name`;
/// they are never regenerated on restore. Generation avoids collisions with
/// the set of existing names. After a bounded number of random attempts it
/// falls back to a deterministic `group-N` name so generation always
/// terminates and still returns a name not already in use.
enum GroupNameGenerator {
    static let adjectives = [
        "amber", "brave", "calm", "copper", "fuzzy",
        "gentle", "hidden", "lucky", "quiet", "silver",
    ]

    static let nouns = [
        "river", "owl", "shell", "forest", "moon",
        "stone", "field", "wave", "cloud", "spark",
    ]

    /// Number of random `adjective-noun` draws to attempt before falling back
    /// to a numbered name.
    static let maxAttempts = 64

    /// Generate a name not present in `existing`.
    ///
    /// Draws random `adjective-noun` combinations up to `maxAttempts` times. If
    /// every draw collides (e.g. the small word lists are exhausted), it walks
    /// `group-N` upward until it finds a free name, guaranteeing the result is
    /// never already in `existing`.
    ///
    /// Randomness is injectable so tests can be deterministic; production calls
    /// use the system generator.
    static func make(existing: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(existing: existing, using: &generator)
    }

    static func make<G: RandomNumberGenerator>(
        existing: Set<String>,
        using generator: inout G
    ) -> String {
        for _ in 0..<maxAttempts {
            let adjective = adjectives.randomElement(using: &generator)!
            let noun = nouns.randomElement(using: &generator)!
            let name = "\(adjective)-\(noun)"
            if !existing.contains(name) { return name }
        }

        // Deterministic fallback. Walk upward so we never return a `group-N`
        // name that already exists.
        var n = existing.count + 1
        while existing.contains("group-\(n)") { n += 1 }
        return "group-\(n)"
    }
}
