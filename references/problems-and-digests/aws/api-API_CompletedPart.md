

# CompletedPart
<a name="API_CompletedPart"></a>

Details of the parts that were uploaded.

## Contents
<a name="API_CompletedPart_Contents"></a>

 ** ChecksumCRC32 **   <a name="AmazonS3-Type-CompletedPart-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32` checksum of the part. This checksum is present if the multipart upload request was created with the `CRC32` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC32C **   <a name="AmazonS3-Type-CompletedPart-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the part. This checksum is present if the multipart upload request was created with the `CRC32C` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC64NVME **   <a name="AmazonS3-Type-CompletedPart-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the part. This checksum is present if the multipart upload request was created with the `CRC64NVME` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumMD5 **   <a name="AmazonS3-Type-CompletedPart-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` digest of the part. This checksum is present if the multipart upload request was created with the `MD5` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA1 **   <a name="AmazonS3-Type-CompletedPart-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` checksum of the part. This checksum is present if the multipart upload request was created with the `SHA1` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA256 **   <a name="AmazonS3-Type-CompletedPart-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` checksum of the part. This checksum is present if the multipart upload request was created with the `SHA256` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA512 **   <a name="AmazonS3-Type-CompletedPart-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` digest of the part. This checksum is present if the multipart upload request was created with the `SHA512` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH128 **   <a name="AmazonS3-Type-CompletedPart-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH128` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH3 **   <a name="AmazonS3-Type-CompletedPart-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH3` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH64 **   <a name="AmazonS3-Type-CompletedPart-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH64` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ETag **   <a name="AmazonS3-Type-CompletedPart-ETag"></a>
Entity tag returned when the part was uploaded.  
Type: String  
Required: No

 ** PartNumber **   <a name="AmazonS3-Type-CompletedPart-PartNumber"></a>
Part number that identifies the part. This is a positive integer between 1 and 10,000.  
+  **General purpose buckets** - In `CompleteMultipartUpload`, when a additional checksum (including `x-amz-checksum-crc32`, `x-amz-checksum-crc32c`, `x-amz-checksum-sha1`, or `x-amz-checksum-sha256`) is applied to each part, the `PartNumber` must start at 1 and the part numbers must be consecutive. Otherwise, Amazon S3 generates an HTTP `400 Bad Request` status code and an `InvalidPartOrder` error code.
+  **Directory buckets** - In `CompleteMultipartUpload`, the `PartNumber` must start at 1 and the part numbers must be consecutive.
Type: Integer  
Required: No

## See Also
<a name="API_CompletedPart_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/CompletedPart) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/CompletedPart) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/CompletedPart) 