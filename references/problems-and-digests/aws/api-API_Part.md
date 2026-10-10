

# Part
<a name="API_Part"></a>

Container for elements related to a part.

## Contents
<a name="API_Part_Contents"></a>

 ** ChecksumCRC32 **   <a name="AmazonS3-Type-Part-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32` checksum of the part. This checksum is present if the object was uploaded with the `CRC32` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC32C **   <a name="AmazonS3-Type-Part-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the part. This checksum is present if the object was uploaded with the `CRC32C` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC64NVME **   <a name="AmazonS3-Type-Part-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the part. This checksum is present if the multipart upload request was created with the `CRC64NVME` checksum algorithm, or if the object was uploaded without a checksum (and Amazon S3 added the default checksum, `CRC64NVME`, to the uploaded object). For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumMD5 **   <a name="AmazonS3-Type-Part-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` digest of the part. This checksum is present if the multipart upload request was created with the `MD5` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA1 **   <a name="AmazonS3-Type-Part-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` checksum of the part. This checksum is present if the object was uploaded with the `SHA1` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA256 **   <a name="AmazonS3-Type-Part-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` checksum of the part. This checksum is present if the object was uploaded with the `SHA256` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA512 **   <a name="AmazonS3-Type-Part-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` digest of the part. This checksum is present if the multipart upload request was created with the `SHA512` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH128 **   <a name="AmazonS3-Type-Part-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH128` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH3 **   <a name="AmazonS3-Type-Part-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH3` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH64 **   <a name="AmazonS3-Type-Part-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the part. This checksum is present if the multipart upload request was created with the `XXHASH64` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ETag **   <a name="AmazonS3-Type-Part-ETag"></a>
Entity tag returned when the part was uploaded.  
Type: String  
Required: No

 ** LastModified **   <a name="AmazonS3-Type-Part-LastModified"></a>
Date and time at which the part was uploaded.  
Type: Timestamp  
Required: No

 ** PartNumber **   <a name="AmazonS3-Type-Part-PartNumber"></a>
Part number identifying the part. This is a positive integer between 1 and 10,000.  
Type: Integer  
Required: No

 ** Size **   <a name="AmazonS3-Type-Part-Size"></a>
Size in bytes of the uploaded part data.  
Type: Long  
Required: No

## See Also
<a name="API_Part_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/Part) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/Part) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/Part) 