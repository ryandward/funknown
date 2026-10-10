{-# LANGUAGE Safe #-}
-- | Literal transcription of the class predicates in http-types,
-- references/http-semantics/code/http-types/Status.hs:783-816. The record is
-- cut down to the one field the predicates read (Status.hs:140-143); the
-- message is a ByteString there and plays no part here.
module Port.HttpTypesStatus
  ( Status (..)
  , statusIsInformational
  , statusIsSuccessful
  , statusIsRedirection
  , statusIsClientError
  , statusIsServerError
  ) where

-- Status.hs:140-143, without statusMessage
data Status = Status
  { statusCode :: Int
  }

-- Status.hs:783-784
statusIsInformational :: Status -> Bool
statusIsInformational (Status {statusCode=code}) = code >= 100 && code < 200

-- Status.hs:791-792
statusIsSuccessful :: Status -> Bool
statusIsSuccessful (Status {statusCode=code}) = code >= 200 && code < 300

-- Status.hs:799-800
statusIsRedirection :: Status -> Bool
statusIsRedirection (Status {statusCode=code}) = code >= 300 && code < 400

-- Status.hs:807-808
statusIsClientError :: Status -> Bool
statusIsClientError (Status {statusCode=code}) = code >= 400 && code < 500

-- Status.hs:815-816
statusIsServerError :: Status -> Bool
statusIsServerError (Status {statusCode=code}) = code >= 500 && code < 600
