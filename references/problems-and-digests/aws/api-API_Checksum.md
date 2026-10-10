

# Checksum
<a name="API_Checksum"></a>

Contains all the possible checksum or digest values for an object.

## Contents
<a name="API_Checksum_Contents"></a>

 ** ChecksumCRC32 **   <a name="AmazonS3-Type-Checksum-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32 checksum` of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC32C **   <a name="AmazonS3-Type-Checksum-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumCRC64NVME **   <a name="AmazonS3-Type-Checksum-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the object. This checksum is present if the object was uploaded with the `CRC64NVME` checksum algorithm, or if the object was uploaded without a checksum (and Amazon S3 added the default checksum, `CRC64NVME`, to the uploaded object). For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumMD5 **   <a name="AmazonS3-Type-Checksum-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` digest of the object. This checksum is present if the object was uploaded with the `MD5` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA1 **   <a name="AmazonS3-Type-Checksum-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` digest of the object. This checksum is only present if the checksum was uploaded with the object. When you use the API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA256 **   <a name="AmazonS3-Type-Checksum-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` digest of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumSHA512 **   <a name="AmazonS3-Type-Checksum-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` digest of the object. This checksum is present if the object was uploaded with the `SHA512` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumType **   <a name="AmazonS3-Type-Checksum-ChecksumType"></a>
The checksum type that is used to calculate the object’s checksum value. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Valid Values: `COMPOSITE | FULL_OBJECT`   
Required: No

 ** ChecksumXXHASH128 **   <a name="AmazonS3-Type-Checksum-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the object. This checksum is present if the object was uploaded with the `XXHASH128` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH3 **   <a name="AmazonS3-Type-Checksum-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the object. This checksum is present if the object was uploaded with the `XXHASH3` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

 ** ChecksumXXHASH64 **   <a name="AmazonS3-Type-Checksum-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the object. This checksum is present if the object was uploaded with the `XXHASH64` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Required: No

## See Also
<a name="API_Checksum_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/Checksum) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/Checksum) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/Checksum) 