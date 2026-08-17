import Security

public enum ArchivePasswordGeneratorError: Error, Equatable, Sendable {
    case lengthTooShort
    case randomSourceFailed(OSStatus)
}

public enum ArchivePasswordGenerator {
    public static let defaultLength = 16

    static let uppercaseCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let lowercaseCharacters = Array("abcdefghijklmnopqrstuvwxyz")
    static let digitCharacters = Array("0123456789")
    static let symbolCharacters = Array("!@#$%^&*()-_=+")
    static let allowedCharacters =
        uppercaseCharacters + lowercaseCharacters + digitCharacters + symbolCharacters

    public static func generate(length: Int = defaultLength) throws -> String {
        guard length >= 4 else {
            throw ArchivePasswordGeneratorError.lengthTooShort
        }

        var characters = [
            try randomElement(from: uppercaseCharacters),
            try randomElement(from: lowercaseCharacters),
            try randomElement(from: digitCharacters),
            try randomElement(from: symbolCharacters),
        ]
        while characters.count < length {
            characters.append(try randomElement(from: allowedCharacters))
        }

        if characters.count > 1 {
            for index in stride(from: characters.count - 1, through: 1, by: -1) {
                let replacementIndex = try randomIndex(upperBound: index + 1)
                characters.swapAt(index, replacementIndex)
            }
        }
        return String(characters)
    }

    private static func randomElement(from characters: [Character]) throws -> Character {
        characters[try randomIndex(upperBound: characters.count)]
    }

    private static func randomIndex(upperBound: Int) throws -> Int {
        precondition(upperBound > 0 && upperBound <= 256)
        let acceptanceLimit = 256 - (256 % upperBound)

        while true {
            var randomByte: UInt8 = 0
            let status = SecRandomCopyBytes(
                kSecRandomDefault,
                MemoryLayout<UInt8>.size,
                &randomByte
            )
            guard status == errSecSuccess else {
                throw ArchivePasswordGeneratorError.randomSourceFailed(status)
            }
            if Int(randomByte) < acceptanceLimit {
                return Int(randomByte) % upperBound
            }
        }
    }
}
