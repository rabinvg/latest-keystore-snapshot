// Copyright © 2017-2018 Trust.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import CryptoSwift
import Foundation
import Security
import TrustCore

/// Key definition.
public struct KeystoreKey {
    /// Wallet type.
    public var type: WalletType

    /// Wallet UUID, optional.
    public var id: String?

    /// Key's address
    public var address: Address?

    /// Key header with encrypted private key and crypto parameters.
    public var crypto: KeystoreKeyHeader

    /// Mnemonic passphrase
    public var passphrase = ""

    /// Key version, must be 3.
    public var version = 3

    /// Default coin for this key.
    public var coin: SLIP.CoinType?

    /// List of active accounts.
    public var activeAccounts = [Account]()

    /// Creates a new `Key` with a password.
    public init(password: String) throws {
        let mnemonic = Crypto.generateMnemonic(strength: 128)
        try self.init(password: password, mnemonic: mnemonic, passphrase: "")
    }

    /// Initializes a `Key` from a JSON wallet.
    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self = try JSONDecoder().decode(KeystoreKey.self, from: data)
    }

    /// Initializes a `Key` by encrypting a private key with a password.
    public init(password: String, key: PrivateKey, coin: SLIP.CoinType?) throws {
        id = UUID().uuidString.lowercased()
        crypto = try KeystoreKeyHeader(password: password, data: key.data)
        self.type = .encryptedKey
        self.coin = coin
    }

    /// Initializes a `Key` by encrypting a mnemonic phrase with a password.
    public init(password: String, mnemonic: String, passphrase: String = "") throws {
        id = UUID().uuidString.lowercased()

        guard let cstring = mnemonic.cString(using: .ascii) else {
            throw EncryptError.invalidMnemonic
        }
        let data = Data(bytes: cstring.map({ UInt8($0) }))
        crypto = try KeystoreKeyHeader(password: password, data: data)

        type = .hierarchicalDeterministicWallet
        self.passphrase = passphrase
    }

    /// Decrypts the key and returns the private key.
    public func decrypt(password: String) throws -> Data {
        let derivedKey: Data
        switch crypto.kdf {
        case "scrypt":
            let scrypt = Scrypt(params: crypto.kdfParams)
            derivedKey = try scrypt.calculate(password: password)
        default:
            throw DecryptError.unsupportedKDF
        }

        let mac = KeystoreKey.computeMAC(prefix: derivedKey[derivedKey.count - 16 ..< derivedKey.count], key: crypto.cipherText)
        if mac != crypto.mac {
            throw DecryptError.invalidPassword
        }

        let decryptionKey = derivedKey[0...15]
        let decryptedPK: [UInt8]
        switch crypto.cipher {
        case "aes-128-ctr":
            let aesCipher = try AES(key: decryptionKey.bytes, blockMode: CTR(iv: crypto.cipherParams.iv.bytes), padding: .noPadding)
            decryptedPK = try aesCipher.decrypt(crypto.cipherText.bytes)
        case "aes-128-cbc":
            let aesCipher = try AES(key: decryptionKey.bytes, blockMode: CBC(iv: crypto.cipherParams.iv.bytes), padding: .noPadding)
            decryptedPK = try aesCipher.decrypt(crypto.cipherText.bytes)
        default:
            throw DecryptError.unsupportedCipher
        }

        return Data(bytes: decryptedPK)
    }

    static func computeMAC(prefix: Data, key: Data) -> Data {
        var data = Data(capacity: prefix.count + key.count)
        data.append(prefix)
        data.append(key)
        return data.sha3(.keccak256)
    }

//    /// Signs a hash with the given password.
//    ///
//    /// - Parameters:
//    ///   - hash: hash to sign
//    ///   - password: key password
//    /// - Returns: signature
//    /// - Throws: `DecryptError` or `Secp256k1Error`
//    public func sign(hash: Data, password: String) throws -> Data {
//        let key = try decrypt(password: password)
//        return try Secp256k1.shared.sign(hash: hash, privateKey: key)
//    }
//
//    /// Signs multiple hashes with the given password.
//    ///
//    /// - Parameters:
//    ///   - hashes: array of hashes to sign
//    ///   - password: key password
//    /// - Returns: [signature]
//    /// - Throws: `DecryptError` or `Secp256k1Error`
//    public func signHashes(_ hashes: [Data], password: String) throws -> [Data] {
//        let key = try decrypt(password: password)
//        return try hashes.map { try Secp256k1.shared.sign(hash: $0, privateKey: key) }
//    }
//
//    /// Generates a unique file name for this key.
//    public func generateFileName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
//        // keyFileName implements the naming convention for keyfiles:
//        // UTC--<created_at UTC ISO8601>-<address hex>
//        return "UTC--\(filenameTimestamp(for: date, in: timeZone))--\(address.data.hexString)"
//    }
//
//    private func filenameTimestamp(for date: Date, in timeZone: TimeZone = .current) -> String {
//        var tz = ""
//        let offset = timeZone.secondsFromGMT()
//        if offset == 0 {
//            tz = "Z"
//        } else {
//            tz = String(format: "%03d00", offset/60)
//        }
//
//        let components = Calendar(identifier: .iso8601).dateComponents(in: timeZone, from: date)
//        return String(format: "%04d-%02d-%02dT%02d-%02d-%02d.%09d%@", components.year!, components.month!, components.day!, components.hour!, components.minute!, components.second!, components.nanosecond!, tz)
//    }
}

public enum DecryptError: Error {
    case unsupportedKDF
    case unsupportedCipher
    case unsupportedCoin
    case invalidCipher
    case invalidPassword
}

public enum EncryptError: Error {
    case invalidMnemonic
}

extension KeystoreKey: Codable {
    enum CodingKeys: String, CodingKey {
        case address
        case type
        case id
        case crypto
        case activeAccounts
        case version
        case coin
    }

    enum UppercaseCodingKeys: String, CodingKey {
        case crypto = "Crypto"
    }

    struct TypeString {
        static let privateKey = "private-key"
        static let mnemonic = "mnemonic"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let altValues = try decoder.container(keyedBy: UppercaseCodingKeys.self)

        switch try values.decodeIfPresent(String.self, forKey: .type) {
        case TypeString.mnemonic?:
            type = .hierarchicalDeterministicWallet
        default:
            type = .encryptedKey
        }

        id = try values.decode(String.self, forKey: .id)
        if let crypto = try? values.decode(KeystoreKeyHeader.self, forKey: .crypto) {
            self.crypto = crypto
        } else {
            // Workaround for myEtherWallet files
            self.crypto = try altValues.decode(KeystoreKeyHeader.self, forKey: .crypto)
        }
        version = try values.decode(Int.self, forKey: .version)
        coin = try values.decodeIfPresent(SLIP.CoinType.self, forKey: .coin)
        address = try values.decodeIfPresent(String.self, forKey: .address).flatMap({
            return KeystoreKey.address(for: coin, addressString: $0)
        })
        activeAccounts = try values.decodeIfPresent([Account].self, forKey: .activeAccounts) ?? []

        if let address = address, activeAccounts.isEmpty {
            let account = Account(wallet: .none, address: address, derivationPath: Ethereum().derivationPath(at: 0))
            activeAccounts.append(account)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch type {
        case .encryptedKey:
            try container.encode(TypeString.privateKey, forKey: .type)
        case .hierarchicalDeterministicWallet:
            try container.encode(TypeString.mnemonic, forKey: .type)
        }
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(address?.description, forKey: .address)
        try container.encode(crypto, forKey: .crypto)
        try container.encode(version, forKey: .version)
        try container.encode(activeAccounts, forKey: .activeAccounts)
        try container.encodeIfPresent(coin, forKey: .coin)
    }

    public static func address(for coin: SLIP.CoinType?, addressString: String) -> Address? {
        guard let coin = coin else {
            return EthereumAddress(data: Data(hex: addressString))
        }
        return blockchain(coin: coin).address(string: addressString)
    }
}

private extension String {
    func drop0x() -> String {
        if hasPrefix("0x") {
            return String(dropFirst(2))
        }
        return self
    }
}

extension SLIP.CoinType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let coinID = try container.decode(Int.self)
        guard let slip = SLIP.CoinType(rawValue: coinID) else {
            throw DecryptError.unsupportedCoin
        }
        self = slip
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
