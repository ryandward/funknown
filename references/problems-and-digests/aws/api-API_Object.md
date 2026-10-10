

# Object
<a name="API_Object"></a>

An object consists of data and its descriptive metadata.

## Contents
<a name="API_Object_Contents"></a>

 ** ChecksumAlgorithm **   <a name="AmazonS3-Type-Object-ChecksumAlgorithm"></a>
The algorithm that was used to create a checksum of the object.  
Type: Array of strings  
Valid Values: `CRC32 | CRC32C | SHA1 | SHA256 | CRC64NVME | SHA512 | MD5 | XXHASH64 | XXHASH3 | XXHASH128`   
Required: No

 ** ChecksumType **   <a name="AmazonS3-Type-Object-ChecksumType"></a>
The checksum type that is used to calculate the object’s checksum value. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Valid Values: `COMPOSITE | FULL_OBJECT`   
Required: No

 ** ETag **   <a name="AmazonS3-Type-Object-ETag"></a>
The entity tag is a hash of the object. The ETag reflects changes only to the contents of an object, not its metadata. The ETag may or may not be an MD5 digest of the object data. Whether or not it is depends on how the object was created and how it is encrypted as described below:  
+ Objects created by the PUT Object, POST Object, or Copy operation, or through the AWS Management Console, and are encrypted by SSE-S3 or plaintext, have ETags that are an MD5 digest of their object data.
+ Objects created by the PUT Object, POST Object, or Copy operation, or through the AWS Management Console, and are encrypted by SSE-C or SSE-KMS, have ETags that are not an MD5 digest of their object data.
+ If an object is created by either the Multipart Upload or Part Copy operation, the ETag is not an MD5 digest, regardless of the method of encryption. If an object is larger than 16 MB, the AWS Management Console will upload or copy that object as a Multipart Upload, and therefore the ETag will not be an MD5 digest.
 **Directory buckets** - MD5 is not supported by directory buckets.
Type: String  
Required: No

 ** Key **   <a name="AmazonS3-Type-Object-Key"></a>
The name that you assign to an object. You use the object key to retrieve the object.  
Type: String  
Length Constraints: Minimum length of 1.  
Required: No

 ** LastModified **   <a name="AmazonS3-Type-Object-LastModified"></a>
Creation date of the object.  
Type: Timestamp  
Required: No

 ** Owner **   <a name="AmazonS3-Type-Object-Owner"></a>
The owner of the object  
 **Directory buckets** - The bucket owner is returned as the object owner.
Type: [Owner](API_Owner.md) data type  
Required: No

 ** RestoreStatus **   <a name="AmazonS3-Type-Object-RestoreStatus"></a>
Specifies the restoration status of an object. Objects in certain storage classes must be restored before they can be retrieved. For more information about these storage classes and how to work with archived objects, see [ Working with archived objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/archived-objects.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets. Directory buckets only support `EXPRESS_ONEZONE` (the S3 Express One Zone storage class) in Availability Zones and `ONEZONE_IA` (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones.
Type: [RestoreStatus](API_RestoreStatus.md) data type  
Required: No

 ** Size **   <a name="AmazonS3-Type-Object-Size"></a>
Size in bytes of the object  
Type: Long  
Required: No

 ** StorageClass **   <a name="AmazonS3-Type-Object-StorageClass"></a>
The class of storage used to store the object.  
 **Directory buckets** - Directory buckets only support `EXPRESS_ONEZONE` (the S3 Express One Zone storage class) in Availability Zones and `ONEZONE_IA` (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones.
Type: String  
Valid Values: `STANDARD | REDUCED_REDUNDANCY | GLACIER | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | DEEP_ARCHIVE | OUTPOSTS | GLACIER_IR | SNOW | EXPRESS_ONEZONE | FSX_OPENZFS | FSX_ONTAP | AWS_BACKUP_WARM | AWS_BACKUP_LOW_COST_WARM`   
Required: No

## See Also
<a name="API_Object_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/Object) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/Object) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/Object) 