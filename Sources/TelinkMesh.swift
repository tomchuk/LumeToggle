import CommonCrypto
import Foundation

/// Telink "classic" BLE mesh crypto, ported from the Lumecube Android app
/// (com.telink.* classes + libTelinkCrypto.so).
enum Telink {
    /// aes_att_encryption: reverse key, reverse input, AES-128-ECB, reverse output.
    static func aes(_ key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        let k = Array(key.reversed()), d = Array(data.reversed())
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        _ = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                    k, 16, nil, d, 16, &out, 16, &moved)
        return Array(out.reversed())
    }

    static func pad16(_ b: [UInt8]) -> [UInt8] { Array((b + [UInt8](repeating: 0, count: 16)).prefix(16)) }
    static func xor(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] { zip(a, b).map { $0 ^ $1 } }
    static func namePass(_ name: String, _ pass: String) -> [UInt8] {
        xor(pad16(Array(name.utf8)), pad16(Array(pass.utf8)))
    }

    /// Written to the pair characteristic (…1914).
    static func loginPacket(name: String, pass: String, randm: [UInt8]) -> [UInt8] {
        var pkt: [UInt8] = [0x0C]
        pkt += randm
        pkt += aes(pad16(randm), namePass(name, pass)).prefix(8)
        return pkt
    }

    /// Takes the value read back from the pair characteristic. Returns nil if the
    /// device's proof doesn't match (wrong mesh name / password).
    static func sessionKey(name: String, pass: String, randm: [UInt8], response r: [UInt8]) -> [UInt8]? {
        guard r.count >= 17 else { return nil }
        let rands = Array(r[1..<9])
        let np = namePass(name, pass)
        var proof = rands
        proof += aes(pad16(rands), np).prefix(8)
        guard Array(r[1..<17]) == proof else { return nil }
        return aes(np, randm + rands)
    }

    /// Written (without response) to the command characteristic (…1912).
    /// mac4 = low 4 bytes of the MAC, as they appear at offset 4 of the manufacturer data.
    static func commandPacket(key: [UInt8], mac4: [UInt8], seq: UInt32, opcode: UInt8,
                              params: [UInt8], dest: UInt16 = 0) -> [UInt8] {
        let s: [UInt8] = [UInt8(seq & 0xFF), UInt8((seq >> 8) & 0xFF), UInt8((seq >> 16) & 0xFF)]
        let iv: [UInt8] = mac4 + [0x01] + s
        var p: [UInt8] = [UInt8(dest & 0xFF), UInt8(dest >> 8), opcode | 0xC0, 0x11, 0x02] + params
        p = Array((p + [UInt8](repeating: 0, count: 15)).prefix(15))
        let r0 = aes(key, pad16(iv + [15]))
        let mic = aes(key, xor(r0, pad16(p)))
        let e = aes(key, pad16([0x00] + iv))
        var out = s
        out += mic.prefix(2)
        out += xor(p, Array(e.prefix(15)))
        return out
    }

    // MARK: - Self-test against vectors from the Python reference implementation

    static func selfTest() {
        let name = "aB3xYz", pass = "4rfv5tgb"
        let randm = [UInt8](1...8)
        let resp = bytes("0d1112131415161718f66eb8d87523291d")
        let login = hex(loginPacket(name: name, pass: pass, randm: randm))
        let sk = sessionKey(name: name, pass: pass, randm: randm, response: resp) ?? []
        let on = hex(commandPacket(key: sk, mac4: [0xFF, 0xEE, 0xDD, 0xCC], seq: 0x123456,
                                   opcode: 0xD0, params: [1, 0, 0]))
        let ok = login == "0c010203040506070826aa62f3641b9dd1"
            && hex(sk) == "51425719648beab6a032c231098f3558"
            && on == "563412e7da30b973c75c8a9bbb006423be9e202b"
        print(ok ? "selftest PASS" : "selftest FAIL\n login \(login)\n sk    \(hex(sk))\n on    \(on)")
    }

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = [], it = hex.makeIterator()
        while let a = it.next(), let b = it.next() { out.append(UInt8(String([a, b]), radix: 16)!) }
        return out
    }
}
