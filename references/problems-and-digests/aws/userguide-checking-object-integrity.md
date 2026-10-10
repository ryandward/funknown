

# Checking object integrity in Amazon S3
<a name="checking-object-integrity"></a>

Amazon S3 provides a range of data protection capabilities throughout an object's storage lifecycle. With Amazon S3, you can use checksum values to verify the integrity of the data that you upload or download. In addition, you can request that another checksum value be calculated for any object that you store in S3.

When uploading, copying, or managing your data, you can choose from several supported checksum algorithms:
+ CRC-64/NVME (`CRC64NVME`)
**Note**  
The `CRC64NVME` checksum algorithm is the default checksum algorithm used for checksum calculations.
+ CRC-32 (`CRC32`)
+ CRC-32C (`CRC32C`)
+ SHA-1 (`SHA1`)
+ SHA-256 (`SHA256`)
+ MD5 (`MD5`)
+ XXHash64 (`XXHASH64`)
+ XXHash3 (`XXHASH3`)
+ XXHash128 (`XXHASH128`)
+ SHA-512 (`SHA512`)

**Note**  
You can provide a precalculated MD5 checksum using the `x-amz-checksum-md5` header. AWS SDKs do not automatically calculate MD5 checksums. For multipart uploads, the Compute checksum operation in S3 Batch Operations can calculate full object MD5 checksums for objects at rest. The legacy `Content-MD5` header remains available for single part uploads using SSE-S3 encryption.

When you upload an object to S3, you can specify the usage of any of these checksum algorithms. For uploads, all AWS-owned clients calculate a checksum of the object and send it with the upload request. S3 then independently calculates a checksum value of the object on the server-side, and validates it with the provided value before storing the object and checksum value. You can also provide precalculated values for these checksum algorithms when you a perform a single part upload or multipart upload (using the full object checksum type for multipart uploads). To use precalculated values with multiple objects, use the AWS CLI or AWS SDKs.

Alternatively, if you want to verify datasets in S3 without the need to restore or download data, you can use the **Compute checksum** operation with S3 Batch Operations. The **Compute checksum** operation allows you to efficiently verify billions of objects in one job request. When the **Compute checksum** operation is performed, S3 calculates the checksum values for a list of objects, at rest. At the end of the job request, you’ll receive an automatically generated integrity report (also known as a completion report) that you can use to confirm that your data set remains intact.

**Topics**
+ [Checking object integrity for data uploads in Amazon S3](checking-object-integrity-upload.md)
+ [Checking object integrity for data at rest in Amazon S3](checking-object-integrity-at-rest.md)