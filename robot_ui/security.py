import hashlib
import os
import hmac

def hash_passcode(passcode_6: str, salt_hex: str | None = None) -> tuple[str, str]:
    # PBKDF2-HMAC-SHA256
    if salt_hex is None:
        salt = os.urandom(16)
        salt_hex = salt.hex()
    else:
        salt = bytes.fromhex(salt_hex)

    dk = hashlib.pbkdf2_hmac("sha256", passcode_6.encode("utf-8"), salt, 150_000)
    return dk.hex(), salt_hex

def verify_passcode(passcode_6: str, stored_hash_hex: str, salt_hex: str) -> bool:
    cand_hash_hex, _ = hash_passcode(passcode_6, salt_hex=salt_hex)
    return hmac.compare_digest(cand_hash_hex, stored_hash_hex)
