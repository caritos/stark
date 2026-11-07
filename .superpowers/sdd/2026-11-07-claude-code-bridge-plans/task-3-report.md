# Task 3 report: bridge codec, URL, splitting
Built BridgeCodec (encode/decode, base64URL, url/parse, split) and added BridgeError.malformed / itemTooLarge(id:).
RED: `cd ios && swift test --filter BridgeCodecTests` failed to compile (BridgeCodec missing). GREEN: 11 tests pass; full `swift test`: 649 tests passed.
Tests cover: round trip, base64url, URL round trip, bad URLs (scheme, host, missing/duplicate/garbage params), garbage/empty/truncated data, 2 MiB zeros bomb, split item cap (300 -> 2 batches), size split (60 x 5000-char noise notes), oversized single item, empty input.
Files: ios/Sources/StarkKit/Bridge/BridgeCodec.swift, BridgeBatch.swift (2 error cases), ios/Tests/StarkKitTests/BridgeCodecTests.swift.
Notes: maxEncodedBytes=32_768, maxDecodedBytes=1 MiB. Decompression of a bomb fully inflates before the size check (bounded by deflate ratio ~1000x of a 32 KiB-capped payload, and signature is verified first in the app). split uses binary search on prefix length to limit encodes. Each batch's real id is generated before sizing, so the size check includes it.
