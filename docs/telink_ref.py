# Reference implementation mirroring the decompiled Lumecube app (com.telink.* classes + libTelinkCrypto.so)
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

def aes(key, data):
    # libTelinkCrypto aes_att_encryption: reverse key, reverse input, AES-128-ECB, reverse output
    c = Cipher(algorithms.AES(bytes(key[::-1])), modes.ECB()).encryptor()
    return bytes((c.update(bytes(data[::-1])) + c.finalize())[::-1])

def java_encrypt(key, data):
    # com.telink.crypto.AES.encrypt(key, data): reverse key & data, ECB, NO output reverse
    c = Cipher(algorithms.AES(bytes(key[::-1])), modes.ECB()).encryptor()
    return bytes(c.update(bytes(data[::-1])) + c.finalize())

pad16 = lambda b: (bytes(b) + bytes(16))[:16]
xor = lambda a, b: bytes(x ^ y for x, y in zip(a, b))
name_pass = lambda n, p: xor(pad16(n.encode()), pad16(p.encode()))

def login_packet_java(name, pw, randm):
    # literal port of GattConnection.meshLogin
    enc = java_encrypt(pad16(randm), name_pass(name, pw))
    pkt = bytearray(17); pkt[0] = 0x0C; pkt[1:9] = randm; pkt[9:17] = enc[8:16]
    pkt[9:17] = pkt[9:17][::-1]
    return bytes(pkt)

def login_packet(name, pw, randm):
    return bytes([0x0C]) + bytes(randm) + aes(pad16(randm), name_pass(name, pw))[:8]

def device_response(name, pw, rands):
    # what a device would answer (used to build a test vector) -- mirrors MeshUtils.getSessionKey's check
    return bytes([0x0D]) + bytes(rands) + aes(pad16(rands), name_pass(name, pw))[:8]

def session_key_java(name, pw, randm, rands):
    np = name_pass(name, pw)
    return java_encrypt(np, bytes(randm) + bytes(rands))[::-1]

def session_key(name, pw, randm, resp):
    rands = resp[1:9]
    np = name_pass(name, pw)
    if resp[1:17] != bytes(rands) + aes(pad16(rands), np)[:8]:
        return None
    return aes(np, bytes(randm) + bytes(rands))

def command_packet(sk, mac4, seq, opcode, params, dest=0):
    s = bytes([seq & 0xff, (seq >> 8) & 0xff, (seq >> 16) & 0xff])
    iv = bytes(mac4) + b'\x01' + s
    p = (bytes([dest & 0xff, dest >> 8, opcode | 0xC0, 0x11, 0x02]) + bytes(params) + bytes(15))[:15]
    r = aes(sk, pad16(iv + bytes([15])))
    r = aes(sk, xor(r, pad16(p)))
    e = aes(sk, pad16(b'\x00' + iv))
    return s + r[:2] + xor(p, e[:15])

if __name__ == '__main__':
    name, pw = 'aB3xYz', '4rfv5tgb'
    randm = bytes(range(1, 9)); rands = bytes(range(0x11, 0x19))
    assert login_packet(name, pw, randm) == login_packet_java(name, pw, randm)
    resp = device_response(name, pw, rands)
    sk = session_key(name, pw, randm, resp)
    assert sk == session_key_java(name, pw, randm, rands)
    assert session_key('wrong', pw, randm, resp) is None
    mac4 = bytes([0xFF, 0xEE, 0xDD, 0xCC])
    print('login ', login_packet(name, pw, randm).hex())
    print('resp  ', resp.hex())
    print('sk    ', sk.hex())
    print('on    ', command_packet(sk, mac4, 0x123456, 0xD0, [1, 0, 0]).hex())
    print('off   ', command_packet(sk, mac4, 0x123457, 0xD0, [0, 0, 0]).hex())
