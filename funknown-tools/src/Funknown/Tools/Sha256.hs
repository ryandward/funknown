{-# LANGUAGE Safe #-}
-- | SHA-256 (FIPS 180-4), so a generated module can name the exact bytes it
-- was generated from without a hashing package outside the GHC distribution.
module Funknown.Tools.Sha256 (sha256Hex) where

import Data.Bits (complement, rotateR, shiftL, shiftR, xor, (.&.), (.|.))
import qualified Data.ByteString as B
import Data.Word (Word32, Word64, Word8)
import Numeric (showHex)

sha256Hex :: B.ByteString -> String
sha256Hex = concatMap hex32 . foldl' compress h0 . blocks . pad
  where
    hex32 w = let s = showHex w "" in replicate (8 - length s) '0' ++ s

h0 :: [Word32]
h0 = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

ks :: [Word32]
ks =
  [ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
  , 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
  , 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
  , 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
  , 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
  , 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
  , 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
  , 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]

-- | Append 0x80, zeros to 56 mod 64, and the bit length as a big-endian Word64.
pad :: B.ByteString -> [Word8]
pad bs = B.unpack bs ++ [0x80] ++ replicate zeros 0 ++ be64 (fromIntegral (B.length bs) * 8)
  where
    zeros = (55 - B.length bs) `mod` 64
    be64 :: Word64 -> [Word8]
    be64 w = [fromIntegral (w `shiftR` (8 * i)) | i <- [7, 6 .. 0]]

blocks :: [Word8] -> [[Word32]]
blocks [] = []
blocks bs = let (b, rest) = splitAt 64 bs in words32 b : blocks rest
  where
    words32 [] = []
    words32 ws = let (w, r) = splitAt 4 ws in foldl' (\a x -> a `shiftL` 8 .|. fromIntegral x) 0 w : words32 r

compress :: [Word32] -> [Word32] -> [Word32]
compress hs block = zipWith (+) hs (foldl' round' hs (zip ks schedule))
  where
    schedule = take 64 (go block)
    go ws@(w0 : w1 : _ : _ : _ : _ : _ : _ : _ : w9 : _ : _ : _ : _ : w14 : _ : _) =
      w0 : go (drop 1 ws ++ [s1 w14 + w9 + s0 w1 + w0])
    go ws = ws
    s0 x = rotateR x 7 `xor` rotateR x 18 `xor` shiftR x 3
    s1 x = rotateR x 17 `xor` rotateR x 19 `xor` shiftR x 10
    round' [a, b, c, d, e, f, g, h] (k, w) =
      let t1 = h + (rotateR e 6 `xor` rotateR e 11 `xor` rotateR e 25) + ((e .&. f) `xor` (complement e .&. g)) + k + w
          t2 = (rotateR a 2 `xor` rotateR a 13 `xor` rotateR a 22) + ((a .&. b) `xor` (a .&. c) `xor` (b .&. c))
       in [t1 + t2, a, b, c, d + t1, e, f, g]
    round' st _ = st
