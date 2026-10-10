

# UploadPart
<a name="API_UploadPart"></a>

Uploads a part in a multipart upload.

**Note**  
In this operation, you provide new data as a part of an object in your request. However, you have an option to specify your existing Amazon S3 object as a data source for the part you are uploading. To upload a part from an existing object, you use the [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html) operation. 

You must initiate a multipart upload (see [CreateMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html)) before you can upload any part. In response to your initiate request, Amazon S3 returns an upload ID, a unique identifier that you must include in your upload part request.

Part numbers can be any number from 1 to 10,000, inclusive. A part number uniquely identifies a part and also defines its position within the object being created. If you upload a new part using the same part number that was used with a previous part, the previously uploaded part is overwritten.

For information about maximum and minimum part sizes and other multipart upload specifications, see [Multipart upload limits](https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html) in the *Amazon S3 User Guide*.

**Note**  
After you initiate multipart upload and upload one or more parts, you must either complete or abort multipart upload in order to stop getting charged for storage of the uploaded parts. Only after you either complete or abort multipart upload, Amazon S3 frees up the parts storage and stops charging you for the parts storage.

For more information on multipart uploads, go to [Multipart Upload Overview](https://docs.aws.amazon.com/AmazonS3/latest/dev/mpuoverview.html) in the *Amazon S3 User Guide *.

**Note**  
 **Directory buckets** - For directory buckets, you must make requests for this API operation to the Zonal endpoint. These endpoints support virtual-hosted-style requests in the format `https://amzn-s3-demo-bucket.s3express-zone-id.region-code.amazonaws.com/key-name `. Path-style requests are not supported. For more information about endpoints in Availability Zones, see [Regional and Zonal endpoints for directory buckets in Availability Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/endpoint-directory-buckets-AZ.html) in the *Amazon S3 User Guide*. For more information about endpoints in Local Zones, see [Concepts for directory buckets in Local Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-lzs-for-directory-buckets.html) in the *Amazon S3 User Guide*.

Permissions  
+  **General purpose bucket permissions** - To perform a multipart upload with encryption using an AWS Key Management Service key, the requester must have permission to the `kms:Decrypt` and `kms:GenerateDataKey` actions on the key. The requester must also have permissions for the `kms:GenerateDataKey` action for the `CreateMultipartUpload` API. Then, the requester needs permissions for the `kms:Decrypt` action on the `UploadPart` and `UploadPartCopy` APIs.

  These permissions are required because Amazon S3 must decrypt and read data from the encrypted file parts before it completes the multipart upload. For more information about KMS permissions, see [Protecting data using server-side encryption with AWS KMS](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html) in the *Amazon S3 User Guide*. For information about the permissions required to use the multipart upload API, see [Multipart upload and permissions](https://docs.aws.amazon.com/AmazonS3/latest/dev/mpuAndPermissions.html) and [Multipart upload API and permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html#mpuAndPermissions) in the *Amazon S3 User Guide*.
+  **Directory bucket permissions** - To grant access to this API operation on a directory bucket, we recommend that you use the [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html) API operation for session-based authorization. Specifically, you grant the `s3express:CreateSession` permission to the directory bucket in a bucket policy or an IAM identity-based policy. Then, you make the `CreateSession` API call on the bucket to obtain a session token. With the session token in your request header, you can make API requests to this operation. After the session token expires, you make another `CreateSession` API call to generate a new session token for use. AWS CLI or SDKs create session and refresh the session token automatically to avoid service interruptions when a session expires. For more information about authorization, see [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html).

  If the object is encrypted with SSE-KMS, you must also have the `kms:GenerateDataKey` and `kms:Decrypt` permissions in IAM identity-based policies and AWS KMS key policies for the AWS KMS key.

Data integrity  
 **General purpose bucket** - To ensure that data is not corrupted traversing the network, specify the `Content-MD5` header in the upload part request. Amazon S3 checks the part data against the provided MD5 value. If they do not match, Amazon S3 returns an error. If the upload request is signed with Signature Version 4, then AWS S3 uses the `x-amz-content-sha256` header as a checksum instead of `Content-MD5`. For more information see [Authenticating Requests: Using the Authorization Header (AWS Signature Version 4)](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-auth-using-authorization-header.html).   
 **Directory buckets** - MD5 is not supported by directory buckets. You can use checksum algorithms to check object integrity.

Encryption  
+  **General purpose bucket** - Server-side encryption is for data encryption at rest. Amazon S3 encrypts your data as it writes it to disks in its data centers and decrypts it when you access it. You have mutually exclusive options to protect data using server-side encryption in Amazon S3, depending on how you choose to manage the encryption keys. Specifically, the encryption key options are Amazon S3 managed keys (SSE-S3), AWS KMS keys (SSE-KMS), and Customer-Provided Keys (SSE-C). Amazon S3 encrypts data with server-side encryption using Amazon S3 managed keys (SSE-S3) by default. You can optionally tell Amazon S3 to encrypt data at rest using server-side encryption with other key options. The option you use depends on whether you want to use KMS keys (SSE-KMS) or provide your own encryption key (SSE-C).

  Server-side encryption is supported by the S3 Multipart Upload operations. Unless you are using a customer-provided encryption key (SSE-C), you don't need to specify the encryption parameters in each UploadPart request. Instead, you only need to specify the server-side encryption parameters in the initial Initiate Multipart request. For more information, see [CreateMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html).
**Note**  
If you have server-side encryption with customer-provided keys (SSE-C) blocked for your general purpose bucket, you will get an HTTP 403 Access Denied error when you specify the SSE-C request headers while writing new data to your bucket. For more information, see [Blocking or unblocking SSE-C for a general purpose bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/blocking-unblocking-s3-c-encryption-gpb.html).

  If you request server-side encryption using a customer-provided encryption key (SSE-C) in your initiate multipart upload request, you must provide identical encryption information in each part upload using the following request headers.
  + x-amz-server-side-encryption-customer-algorithm
  + x-amz-server-side-encryption-customer-key
  + x-amz-server-side-encryption-customer-key-MD5

   For more information, see [Using Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html) in the *Amazon S3 User Guide*.
+  **Directory buckets ** - For directory buckets, there are only two supported options for server-side encryption: server-side encryption with Amazon S3 managed keys (SSE-S3) (`AES256`) and server-side encryption with AWS KMS keys (SSE-KMS) (`aws:kms`).

Special errors  
+ Error Code: `NoSuchUpload` 
  + Description: The specified multipart upload does not exist. The upload ID might be invalid, or the multipart upload might have been aborted or completed.
  + HTTP Status Code: 404 Not Found 
  + SOAP Fault Code Prefix: Client

HTTP Host header syntax  
 **Directory buckets ** - The HTTP Host header syntax is ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`.

The following operations are related to `UploadPart`:
+  [CreateMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html) 
+  [CompleteMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html) 
+  [AbortMultipartUpload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_AbortMultipartUpload.html) 
+  [ListParts](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListParts.html) 
+  [ListMultipartUploads](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListMultipartUploads.html) 

**Important**  
You must URL encode any signed header values that contain spaces. For example, if your header value is `my file.txt`, containing two spaces after `my`, you must URL encode this value to `my%20%20file.txt`.

## Request Syntax
<a name="API_UploadPart_RequestSyntax"></a>

```
PUT /{{Key+}}?partNumber={{PartNumber}}&uploadId={{UploadId}} HTTP/1.1
Host: {{Bucket}}.s3.amazonaws.com
Content-Length: {{ContentLength}}
Content-MD5: {{ContentMD5}}
x-amz-sdk-checksum-algorithm: {{ChecksumAlgorithm}}
x-amz-checksum-crc32: {{ChecksumCRC32}}
x-amz-checksum-crc32c: {{ChecksumCRC32C}}
x-amz-checksum-crc64nvme: {{ChecksumCRC64NVME}}
x-amz-checksum-sha1: {{ChecksumSHA1}}
x-amz-checksum-sha256: {{ChecksumSHA256}}
x-amz-checksum-sha512: {{ChecksumSHA512}}
x-amz-checksum-md5: {{ChecksumMD5}}
x-amz-checksum-xxhash64: {{ChecksumXXHASH64}}
x-amz-checksum-xxhash3: {{ChecksumXXHASH3}}
x-amz-checksum-xxhash128: {{ChecksumXXHASH128}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key: {{SSECustomerKey}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-request-payer: {{RequestPayer}}
x-amz-expected-bucket-owner: {{ExpectedBucketOwner}}

{{Body}}
```

## URI Request Parameters
<a name="API_UploadPart_RequestParameters"></a>

The request uses the following URI parameters.

 ** [Bucket](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-Bucket"></a>
The name of the bucket to which the multipart upload was initiated.  
 **Directory buckets** - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format ` bucket-base-name--zone-id--x-s3` (for example, ` amzn-s3-demo-bucket--usw2-az1--x-s3`). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the *Amazon S3 User Guide*.  
 **Access points** - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form *AccessPointName*-*AccountId*.s3-accesspoint.*Region*.amazonaws.com. When using this action with an access point through the AWS SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the *Amazon S3 User Guide*.  
Object Lambda access points are not supported by directory buckets.
 **S3 on Outposts** - When you use this action with S3 on Outposts, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form ` AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com`. When you use this action with S3 on Outposts, the destination bucket must be the Outposts access point ARN or the access point alias. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the *Amazon S3 User Guide*.  
Required: Yes

 ** [Content-Length](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ContentLength"></a>
Size of the body in bytes. This parameter is useful when the size of the body cannot be determined automatically.

 ** [Content-MD5](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ContentMD5"></a>
The Base64 encoded 128-bit MD5 digest of the part data. This parameter is auto-populated when using the command from the CLI. This parameter is required if object lock parameters are specified.  
This functionality is not supported for directory buckets.

 ** [Key](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-uri-uri-Key"></a>
Object key for which the multipart upload was initiated.  
Length Constraints: Minimum length of 1.  
Required: Yes

 ** [partNumber](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-uri-querystring-PartNumber"></a>
Part number of part being uploaded. This is a positive integer between 1 and 10,000.  
Required: Yes

 ** [uploadId](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-uri-querystring-UploadId"></a>
Upload ID identifying the multipart upload whose part is being uploaded.  
Required: Yes

 ** [x-amz-checksum-crc32](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumCRC32"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit `CRC32` checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc32c](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumCRC32C"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit `CRC32C` checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc64nvme](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumCRC64NVME"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `CRC64NVME` checksum of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-md5](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumMD5"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 128-bit `MD5` digest of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha1](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumSHA1"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 160-bit `SHA1` digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha256](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumSHA256"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 256-bit `SHA256` digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha512](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumSHA512"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 512-bit `SHA512` digest of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash128](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumXXHASH128"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 128-bit `XXHASH128` checksum of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash3](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumXXHASH3"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `XXHASH3` checksum of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash64](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumXXHASH64"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `XXHASH64` checksum of the part. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-expected-bucket-owner](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ExpectedBucketOwner"></a>
The account ID of the expected bucket owner. If the account ID that you provide does not match the actual owner of the bucket, the request fails with the HTTP status code `403 Forbidden` (access denied).

 ** [x-amz-request-payer](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-RequestPayer"></a>
Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for the corresponding charges. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-sdk-checksum-algorithm](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-ChecksumAlgorithm"></a>
Indicates the algorithm used to create the checksum for the object when you use the SDK. This header will not provide any additional functionality if you don't use the SDK. When you send this header, there must be a corresponding `x-amz-checksum` or `x-amz-trailer` header sent. Otherwise, Amazon S3 fails the request with the HTTP status code `400 Bad Request`. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
If you provide an individual checksum, Amazon S3 ignores any provided `ChecksumAlgorithm` parameter.  
This checksum algorithm must be the same for all parts and it match the checksum value supplied in the `CreateMultipartUpload` request.  
Valid Values: `CRC32 | CRC32C | SHA1 | SHA256 | CRC64NVME | SHA512 | MD5 | XXHASH64 | XXHASH3 | XXHASH128` 

 ** [x-amz-server-side-encryption-customer-algorithm](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-SSECustomerAlgorithm"></a>
Specifies the algorithm to use when encrypting the object (for example, AES256).  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-SSECustomerKey"></a>
Specifies the customer-provided encryption key for Amazon S3 to use in encrypting data. This value is used to store the object and then it is discarded; Amazon S3 does not store the encryption key. The key must be appropriate for use with the algorithm specified in the `x-amz-server-side-encryption-customer-algorithm header`. This must be the same encryption key specified in the initiate multipart upload request.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-header-SSECustomerKeyMD5"></a>
Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error.  
This functionality is not supported for directory buckets.

## Request Body
<a name="API_UploadPart_RequestBody"></a>

The request accepts the following binary data.

 ** [Body](#API_UploadPart_RequestSyntax) **   <a name="AmazonS3-UploadPart-request-Body"></a>

## Response Syntax
<a name="API_UploadPart_ResponseSyntax"></a>

```
HTTP/1.1 200
x-amz-server-side-encryption: {{ServerSideEncryption}}
ETag: {{ETag}}
x-amz-checksum-crc32: {{ChecksumCRC32}}
x-amz-checksum-crc32c: {{ChecksumCRC32C}}
x-amz-checksum-crc64nvme: {{ChecksumCRC64NVME}}
x-amz-checksum-sha1: {{ChecksumSHA1}}
x-amz-checksum-sha256: {{ChecksumSHA256}}
x-amz-checksum-sha512: {{ChecksumSHA512}}
x-amz-checksum-md5: {{ChecksumMD5}}
x-amz-checksum-xxhash64: {{ChecksumXXHASH64}}
x-amz-checksum-xxhash3: {{ChecksumXXHASH3}}
x-amz-checksum-xxhash128: {{ChecksumXXHASH128}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-server-side-encryption-aws-kms-key-id: {{SSEKMSKeyId}}
x-amz-server-side-encryption-bucket-key-enabled: {{BucketKeyEnabled}}
x-amz-request-charged: {{RequestCharged}}
```

## Response Elements
<a name="API_UploadPart_ResponseElements"></a>

If the action is successful, the service sends back an HTTP 200 response.

The response returns the following HTTP headers.

 ** [ETag](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ETag"></a>
Entity tag for the uploaded object.

 ** [x-amz-checksum-crc32](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc32c](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc64nvme](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-md5](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha1](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha256](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha512](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash128](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash3](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-xxhash64](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the part. This will only be present if the checksum was provided in the request. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-request-charged](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-RequestCharged"></a>
If present, indicates that the requester was successfully charged for the request. For more information, see [Using Requester Pays buckets for storage transfers and usage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html) in the *Amazon Simple Storage Service user guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-server-side-encryption](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-ServerSideEncryption"></a>
The server-side encryption algorithm used when you store this object in Amazon S3 or Amazon FSx.  
When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is `aws:fsx`.
Valid Values: `AES256 | aws:fsx | aws:backup | aws:kms | aws:kms:dsse` 

 ** [x-amz-server-side-encryption-aws-kms-key-id](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-SSEKMSKeyId"></a>
If present, indicates the ID of the KMS key that was used for object encryption.

 ** [x-amz-server-side-encryption-bucket-key-enabled](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-BucketKeyEnabled"></a>
Indicates whether the multipart upload uses an S3 Bucket Key for server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS).

 ** [x-amz-server-side-encryption-customer-algorithm](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-SSECustomerAlgorithm"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to confirm the encryption algorithm that's used.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_UploadPart_ResponseSyntax) **   <a name="AmazonS3-UploadPart-response-header-SSECustomerKeyMD5"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to provide the round-trip message integrity verification of the customer-provided encryption key.  
This functionality is not supported for directory buckets.

## Examples
<a name="API_UploadPart_Examples"></a>

### Sample Request for general purpose buckets
<a name="API_UploadPart_Example_1"></a>

The following PUT request uploads a part (part number 1) in a multipart upload. The request includes the upload ID that you get in response to your Initiate Multipart Upload request.

```
PUT /my-movie.m2ts?partNumber=1&uploadId=VCVsb2FkIElEIGZvciBlbZZpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZR HTTP/1.1
Host: example-bucket.s3.<Region>.amazonaws.com
Date:  Mon, 1 Nov 2010 20:34:56 GMT
Content-Length: 10485760
Content-MD5: pUNXr/BjKK5G2UKvaRRrOA==
Authorization: authorization string

***part data omitted***
```

### Sample Response for general purpose buckets
<a name="API_UploadPart_Example_2"></a>

The response includes the ETag header. You need to retain this value for use when you send the Complete Multipart Upload request.

```
HTTP/1.1 200 OK
x-amz-id-2: Vvag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==
x-amz-request-id: 656c76696e6727732072657175657374
Date:  Mon, 1 Nov 2010 20:34:56 GMT
ETag: "b54357faf0632cce46e942fa68356b38"
Content-Length: 0
Connection: keep-alive
Server: AmazonS3
```

### Example for general purpose buckets: Upload a part with an encryption key in the request for server-side encryption
<a name="API_UploadPart_Example_3"></a>

If you initiated a multipart upload with a request to save an object using server-side encryption with a customer-provided encryption key, each part upload must also include the same set of encryption-specific headers as shown in the following example request.

```
PUT /example-object?partNumber=1&uploadId=EXAMPLEJZ6e0YupT2h66iePQCc9IEbYbDUy4RTpMeoSMLPRp8Z5o1u8feSRonpvnWsKKG35tI2LB9VDPiCgTy.Gq2VxQLYjrue4Nq.NBdqI- HTTP/1.1
Host: example-bucket.s3.<Region>.amazonaws.com
Authorization: authorization string   
Date: Wed, 28 May 2014 19:40:11 +0000   
x-amz-server-side-encryption-customer-key: g0lCfA3Dv40jZz5SQJ1ZukLRFqtI5WorC/8SEEXAMPLE   
x-amz-server-side-encryption-customer-key-MD5: ZjQrne1X/iTcskbY2example   
x-amz-server-side-encryption-customer-algorithm: AES256
```

### Example for general purpose buckets
<a name="API_UploadPart_Example_4"></a>

In the response, Amazon S3 returns encryption-specific headers providing the encryption algorithm used and MD5 digest of the encryption key you provided in the request.

```
HTTP/1.1 100 Continue   HTTP/1.1 200 OK
x-amz-id-2: Zn8bf8aEFQ+kBnGPBc/JaAf9SoWM68QDPS9+SyFwkIZOHUG2BiRLZi5oXw4cOCEt
x-amz-request-id: 5A37448A37622243
Date: Wed, 28 May 2014 19:40:12 GMT
ETag: "7e10e7d25dc4581d89b9285be5f384fd"
x-amz-server-side-encryption-customer-algorithm: AES256
x-amz-server-side-encryption-customer-key-MD5: ZjQrne1X/iTcskbY2example
```

## See Also
<a name="API_UploadPart_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS Command Line Interface V2](https://docs.aws.amazon.com/goto/cli2/s3-2006-03-01/UploadPart) 
+  [AWS SDK for .NET V4](https://docs.aws.amazon.com/goto/DotNetSDKV4/s3-2006-03-01/UploadPart) 
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/UploadPart) 
+  [AWS SDK for Go v2](https://docs.aws.amazon.com/goto/SdkForGoV2/s3-2006-03-01/UploadPart) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/UploadPart) 
+  [AWS SDK for JavaScript V3](https://docs.aws.amazon.com/goto/SdkForJavaScriptV3/s3-2006-03-01/UploadPart) 
+  [AWS SDK for Kotlin](https://docs.aws.amazon.com/goto/SdkForKotlin/s3-2006-03-01/UploadPart) 
+  [AWS SDK for PHP V3](https://docs.aws.amazon.com/goto/SdkForPHPV3/s3-2006-03-01/UploadPart) 
+  [AWS SDK for Python (Boto3)](https://docs.aws.amazon.com/goto/boto3/s3-2006-03-01/UploadPart) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/UploadPart) 