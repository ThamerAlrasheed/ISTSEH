from app.core.security import create_access_token, decode_access_token, hash_password, hash_token, verify_password


def test_password_hash_and_verify() -> None:
    password_hash = hash_password("Password123")
    assert verify_password("Password123", password_hash)
    assert not verify_password("wrong", password_hash)


def test_access_token_round_trip() -> None:
    token = create_access_token("user-id", "regular")
    payload = decode_access_token(token)
    assert payload.sub == "user-id"
    assert payload.role == "regular"
    assert payload.token_type == "access"


def test_hash_token_is_stable() -> None:
    assert hash_token("abc") == hash_token("abc")
