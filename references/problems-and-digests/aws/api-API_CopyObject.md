

# CopyObject
<a name="API_CopyObject"></a>

Creates a copy of an object that is already stored in Amazon S3.

**Important**  
End of support notice: As of October 1, 2025, Amazon S3 has discontinued support for Email Grantee Access Control Lists (ACLs). If you attempt to use an Email Grantee ACL in a request after October 1, 2025, the request will receive an `HTTP 405` (Method Not Allowed) error.  
This change affects the following AWS Regions: US East (N. Virginia), US West (N. California), US West (Oregon), Asia Pacific (Singapore), Asia Pacific (Sydney), Asia Pacific (Tokyo), Europe (Ireland), and South America (São Paulo).

**Note**  
You can store individual objects of up to 50 TB in Amazon S3. You create a copy of your object up to 5 GB in size in a single atomic action using this API. However, to copy an object greater than 5 GB, you must use the multipart upload Upload Part - Copy (UploadPartCopy) API. For more information, see [Copy Object Using the REST Multipart Upload API](https://docs.aws.amazon.com/AmazonS3/latest/dev/CopyingObjctsUsingRESTMPUapi.html).

You can copy individual objects between general purpose buckets, between directory buckets, and between general purpose buckets and directory buckets.

**Note**  
Amazon S3 supports copy operations using Multi-Region Access Points only as a destination when using the Multi-Region Access Point ARN. 
 **Directory buckets ** - For directory buckets, you must make requests for this API operation to the Zonal endpoint. These endpoints support virtual-hosted-style requests in the format `https://amzn-s3-demo-bucket.s3express-zone-id.region-code.amazonaws.com/key-name `. Path-style requests are not supported. For more information about endpoints in Availability Zones, see [Regional and Zonal endpoints for directory buckets in Availability Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/endpoint-directory-buckets-AZ.html) in the *Amazon S3 User Guide*. For more information about endpoints in Local Zones, see [Concepts for directory buckets in Local Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-lzs-for-directory-buckets.html) in the *Amazon S3 User Guide*.
VPC endpoints don't support cross-Region requests (including copies). If you're using VPC endpoints, your source and destination buckets should be in the same AWS Region as your VPC endpoint.

Both the Region that you want to copy the object from and the Region that you want to copy the object to must be enabled for your account. For more information about how to enable a Region for your account, see [Enable or disable a Region for standalone accounts](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-regions.html#manage-acct-regions-enable-standalone) in the * AWS Account Management Guide*.

**Important**  
Amazon S3 transfer acceleration does not support cross-Region copies. If you request a cross-Region copy using a transfer acceleration endpoint, you get a `400 Bad Request` error. For more information, see [Transfer Acceleration](https://docs.aws.amazon.com/AmazonS3/latest/dev/transfer-acceleration.html).

Authentication and authorization  
All `CopyObject` requests must be authenticated and signed by using IAM credentials (access key ID and secret access key for the IAM identities). All headers with the `x-amz-` prefix, including `x-amz-copy-source`, must be signed. For more information, see [REST Authentication](https://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html).  
 **Directory buckets** - You must use the IAM credentials to authenticate and authorize your access to the `CopyObject` API operation, instead of using the temporary security credentials through the `CreateSession` API operation.  
 AWS CLI or SDKs handles authentication and authorization on your behalf.

Permissions  
You must have *read* access to the source object and *write* access to the destination bucket.  
+  **General purpose bucket permissions** - You must have permissions in an IAM policy based on the source and destination bucket types in a `CopyObject` operation.
  + If the source object is in a general purpose bucket, you must have ** `s3:GetObject` ** permission to read the source object that is being copied. 
  + If the destination bucket is a general purpose bucket, you must have ** `s3:PutObject` ** permission to write the object copy to the destination bucket. 
+  **Directory bucket permissions** - You must have permissions in a bucket policy or an IAM identity-based policy based on the source and destination bucket types in a `CopyObject` operation.
  + If the source object that you want to copy is in a directory bucket, you must have the ** `s3express:CreateSession` ** permission in the `Action` element of a policy to read the object. If no session mode is specified, the session will be created with the maximum allowable privilege, attempting `ReadWrite` first, then `ReadOnly` if `ReadWrite` is not permitted. If you want to explicitly restrict the access to be read-only, you can set the `s3express:SessionMode` condition key to `ReadOnly` on the copy source bucket.
  + If the copy destination is a directory bucket, you must have the ** `s3express:CreateSession` ** permission in the `Action` element of a policy to write the object to the destination. The `s3express:SessionMode` condition key can't be set to `ReadOnly` on the copy destination bucket. 

  If the object is encrypted with SSE-KMS, you must also have the `kms:GenerateDataKey` and `kms:Decrypt` permissions in IAM identity-based policies and AWS KMS key policies for the AWS KMS key.

  For example policies, see [Example bucket policies for S3 Express One Zone](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-security-iam-example-bucket-policies.html) and [AWS Identity and Access Management (IAM) identity-based policies for S3 Express One Zone](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-security-iam-identity-policies.html) in the *Amazon S3 User Guide*.

Response and special errors  
When the request is an HTTP 1.1 request, the response is chunk encoded. When the request is not an HTTP 1.1 request, the response would not contain the `Content-Length`. You always need to read the entire response body to check if the copy succeeds.   
+ If the copy is successful, you receive a response with information about the copied object.
+ A copy request might return an error when Amazon S3 receives the copy request or while Amazon S3 is copying the files. A `200 OK` response can contain either a success or an error.
  + If the error occurs before the copy action starts, you receive a standard Amazon S3 error.
  + If the error occurs during the copy operation, the error response is embedded in the `200 OK` response. For example, in a cross-region copy, you may encounter throttling and receive a `200 OK` response. For more information, see [Resolve the Error 200 response when copying objects to Amazon S3](https://repost.aws/knowledge-center/s3-resolve-200-internalerror). The `200 OK` status code means the copy was accepted, but it doesn't mean the copy is complete. Another example is when you disconnect from Amazon S3 before the copy is complete, Amazon S3 might cancel the copy and you may receive a `200 OK` response. You must stay connected to Amazon S3 until the entire response is successfully received and processed.

    If you call this API operation directly, make sure to design your application to parse the content of the response and handle it appropriately. If you use AWS SDKs, SDKs handle this condition. The SDKs detect the embedded error and apply error handling per your configuration settings (including automatically retrying the request as appropriate). If the condition persists, the SDKs throw an exception (or, for the SDKs that don't use exceptions, they return an error).

Charge  
The copy request charge is based on the storage class and Region that you specify for the destination object. The request can also result in a data retrieval charge for the source if the source storage class bills for data retrieval. If the copy source is in a different region, the data transfer is billed to the copy source account. For pricing information, see [Amazon S3 pricing](http://aws.amazon.com/s3/pricing/).

HTTP Host header syntax  
+  **Directory buckets ** - The HTTP Host header syntax is ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`.
+  **Amazon S3 on Outposts** - When you use this action with S3 on Outposts through the REST API, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form ` AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com`. The hostname isn't required when you use the AWS CLI or SDKs.

The following operations are related to `CopyObject`:
+  [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html) 
+  [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html) 

**Important**  
You must URL encode any signed header values that contain spaces. For example, if your header value is `my file.txt`, containing two spaces after `my`, you must URL encode this value to `my%20%20file.txt`.

## Request Syntax
<a name="API_CopyObject_RequestSyntax"></a>

```
PUT /{{Key+}} HTTP/1.1
Host: {{Bucket}}.s3.amazonaws.com
x-amz-acl: {{ACL}}
Cache-Control: {{CacheControl}}
x-amz-checksum-algorithm: {{ChecksumAlgorithm}}
Content-Disposition: {{ContentDisposition}}
Content-Encoding: {{ContentEncoding}}
Content-Language: {{ContentLanguage}}
Content-Type: {{ContentType}}
x-amz-copy-source: {{CopySource}}
x-amz-copy-source-if-match: {{CopySourceIfMatch}}
x-amz-copy-source-if-modified-since: {{CopySourceIfModifiedSince}}
x-amz-copy-source-if-none-match: {{CopySourceIfNoneMatch}}
x-amz-copy-source-if-unmodified-since: {{CopySourceIfUnmodifiedSince}}
Expires: {{Expires}}
x-amz-grant-full-control: {{GrantFullControl}}
x-amz-grant-read: {{GrantRead}}
x-amz-grant-read-acp: {{GrantReadACP}}
x-amz-grant-write-acp: {{GrantWriteACP}}
If-Match: {{IfMatch}}
If-None-Match: {{IfNoneMatch}}
x-amz-metadata-directive: {{MetadataDirective}}
x-amz-tagging-directive: {{TaggingDirective}}
x-amz-object-annotation-directive: {{AnnotationDirective}}
x-amz-server-side-encryption: {{ServerSideEncryption}}
x-amz-storage-class: {{StorageClass}}
x-amz-website-redirect-location: {{WebsiteRedirectLocation}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key: {{SSECustomerKey}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-server-side-encryption-aws-kms-key-id: {{SSEKMSKeyId}}
x-amz-server-side-encryption-context: {{SSEKMSEncryptionContext}}
x-amz-server-side-encryption-bucket-key-enabled: {{BucketKeyEnabled}}
x-amz-copy-source-server-side-encryption-customer-algorithm: {{CopySourceSSECustomerAlgorithm}}
x-amz-copy-source-server-side-encryption-customer-key: {{CopySourceSSECustomerKey}}
x-amz-copy-source-server-side-encryption-customer-key-MD5: {{CopySourceSSECustomerKeyMD5}}
x-amz-request-payer: {{RequestPayer}}
x-amz-tagging: {{Tagging}}
x-amz-object-lock-mode: {{ObjectLockMode}}
x-amz-object-lock-retain-until-date: {{ObjectLockRetainUntilDate}}
x-amz-object-lock-legal-hold: {{ObjectLockLegalHoldStatus}}
x-amz-object-lock-event-hold: {{ObjectLockEventHold}}
x-amz-object-lock-event-hold-duration-days: {{ObjectLockEventHoldDurationDays}}
x-amz-object-lock-event-hold-duration-years: {{ObjectLockEventHoldDurationYears}}
x-amz-expected-bucket-owner: {{ExpectedBucketOwner}}
x-amz-source-expected-bucket-owner: {{ExpectedSourceBucketOwner}}
```

## URI Request Parameters
<a name="API_CopyObject_RequestParameters"></a>

The request uses the following URI parameters.

 ** [Bucket](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-Bucket"></a>
The name of the destination bucket.  
 **Directory buckets** - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format ` bucket-base-name--zone-id--x-s3` (for example, ` amzn-s3-demo-bucket--usw2-az1--x-s3`). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the *Amazon S3 User Guide*.  
Copying objects across different AWS Regions isn't supported when the source or destination bucket is in AWS Local Zones. The source and destination buckets must have the same parent AWS Region. Otherwise, you get an HTTP `400 Bad Request` error with the error code `InvalidRequest`.
 **Access points** - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form *AccessPointName*-*AccountId*.s3-accesspoint.*Region*.amazonaws.com. When using this action with an access point through the AWS SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the *Amazon S3 User Guide*.  
Object Lambda access points are not supported by directory buckets.
 **S3 on Outposts** - When you use this action with S3 on Outposts, you must use the Outpost bucket access point ARN or the access point alias for the destination bucket. You can only copy objects within the same Outpost bucket. It's not supported to copy objects across different AWS Outposts, between buckets on the same Outposts, or between Outposts buckets and any other bucket types. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the *S3 on Outposts guide*. When you use this action with S3 on Outposts through the REST API, you must direct requests to the S3 on Outposts hostname, in the format ` AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com`. The hostname isn't required when you use the AWS CLI or SDKs.   
Required: Yes

 ** [Cache-Control](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CacheControl"></a>
Specifies the caching behavior along the request/reply chain.

 ** [Content-Disposition](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ContentDisposition"></a>
Specifies presentational information for the object. Indicates whether an object should be displayed in a web browser or downloaded as a file. It allows specifying the desired filename for the downloaded file.

 ** [Content-Encoding](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ContentEncoding"></a>
Specifies what content encodings have been applied to the object and thus what decoding mechanisms must be applied to obtain the media-type referenced by the Content-Type header field.  
For directory buckets, only the `aws-chunked` value is supported in this header field.

 ** [Content-Language](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ContentLanguage"></a>
The language the content is in.

 ** [Content-Type](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ContentType"></a>
A standard MIME type that describes the format of the object data.

 ** [Expires](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-Expires"></a>
The date and time at which the object is no longer cacheable.

 ** [If-Match](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-IfMatch"></a>
Copies the object if the entity tag (ETag) of the destination object matches the specified tag. If the ETag values do not match, the operation returns a `412 Precondition Failed` error. If a concurrent operation occurs during the upload S3 returns a `409 ConditionalRequestConflict` response. On a 409 failure you should fetch the object's ETag and retry the upload.  
Expects the ETag value as a string.  
For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).

 ** [If-None-Match](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-IfNoneMatch"></a>
Copies the object only if the object key name at the destination does not already exist in the bucket specified. Otherwise, Amazon S3 returns a `412 Precondition Failed` error. If a concurrent operation occurs during the upload S3 returns a `409 ConditionalRequestConflict` response. On a 409 failure you should retry the upload.  
Expects the '\*' (asterisk) character.  
For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).

 ** [Key](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-uri-uri-Key"></a>
The key of the destination object.  
Length Constraints: Minimum length of 1.  
Required: Yes

 ** [x-amz-acl](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ACL"></a>
The canned access control list (ACL) to apply to the object.  
When you copy an object, the ACL metadata is not preserved and is set to `private` by default. Only the owner has full access control. To override the default ACL setting, specify a new ACL when you generate a copy request. For more information, see [Using ACLs](https://docs.aws.amazon.com/AmazonS3/latest/dev/S3_ACLs_UsingACLs.html).   
If the destination bucket that you're copying objects to uses the bucket owner enforced setting for S3 Object Ownership, ACLs are disabled and no longer affect permissions. Buckets that use this setting only accept `PUT` requests that don't specify an ACL or `PUT` requests that specify bucket owner full control ACLs, such as the `bucket-owner-full-control` canned ACL or an equivalent form of this ACL expressed in the XML format. For more information, see [Controlling ownership of objects and disabling ACLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) in the *Amazon S3 User Guide*.  
+ If your destination bucket uses the bucket owner enforced setting for Object Ownership, all objects written to the bucket by any account will be owned by the bucket owner.
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.
Valid Values: `private | public-read | public-read-write | authenticated-read | aws-exec-read | bucket-owner-read | bucket-owner-full-control` 

 ** [x-amz-checksum-algorithm](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ChecksumAlgorithm"></a>
Indicates the algorithm that you want Amazon S3 to use to create the checksum for the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
When you copy an object, if the source object has a checksum, that checksum value will be copied to the new object by default. If the `CopyObject` request does not include this `x-amz-checksum-algorithm` header, the checksum algorithm will be copied from the source object to the destination object (if it's present on the source object). You can optionally specify a different checksum algorithm to use with the `x-amz-checksum-algorithm` header. Unrecognized or unsupported values will respond with the HTTP status code `400 Bad Request`.  
For directory buckets, when you use AWS SDKs, `CRC32` is the default checksum algorithm that's used for performance.
Valid Values: `CRC32 | CRC32C | SHA1 | SHA256 | CRC64NVME | SHA512 | MD5 | XXHASH64 | XXHASH3 | XXHASH128` 

 ** [x-amz-copy-source](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySource"></a>
Specifies the source object for the copy operation. The source object can be up to 5 GB. If the source object is an object that was uploaded by using a multipart upload, the object copy will be a single part object after the source object is copied to the destination bucket.  
You specify the value of the copy source in one of two formats, depending on whether you want to access the source object through an [access point](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html):  
+ For objects not accessed through an access point, specify the name of the source bucket and the key of the source object, separated by a slash (/). For example, to copy the object `reports/january.pdf` from the general purpose bucket `awsexamplebucket`, use `awsexamplebucket/reports/january.pdf`. The value must be URL-encoded. To copy the object `reports/january.pdf` from the directory bucket `awsexamplebucket--use1-az5--x-s3`, use `awsexamplebucket--use1-az5--x-s3/reports/january.pdf`. The value must be URL-encoded.
+ For objects accessed through access points, specify the Amazon Resource Name (ARN) of the object as accessed through the access point, in the format `arn:aws:s3:<Region>:<account-id>:accesspoint/<access-point-name>/object/<key>`. For example, to copy the object `reports/january.pdf` through access point `my-access-point` owned by account `123456789012` in Region `us-west-2`, use the URL encoding of `arn:aws:s3:us-west-2:123456789012:accesspoint/my-access-point/object/reports/january.pdf`. The value must be URL encoded.
**Note**  
Amazon S3 supports copy operations using Access points only when the source and destination buckets are in the same AWS Region.
Access points are not supported by directory buckets.

  Alternatively, for objects accessed through Amazon S3 on Outposts, specify the ARN of the object as accessed in the format `arn:aws:s3-outposts:<Region>:<account-id>:outpost/<outpost-id>/object/<key>`. For example, to copy the object `reports/january.pdf` through outpost `my-outpost` owned by account `123456789012` in Region `us-west-2`, use the URL encoding of `arn:aws:s3-outposts:us-west-2:123456789012:outpost/my-outpost/object/reports/january.pdf`. The value must be URL-encoded. 
If your source bucket versioning is enabled, the `x-amz-copy-source` header by default identifies the current version of an object to copy. If the current version is a delete marker, Amazon S3 behaves as if the object was deleted. To copy a different version, use the `versionId` query parameter. Specifically, append `?versionId=<version-id>` to the value (for example, `awsexamplebucket/reports/january.pdf?versionId=QUpfdndhfd8438MNFDN93jdnJFkdmqnh893`). If you don't specify a version ID, Amazon S3 copies the latest version of the source object.  
If you enable versioning on the destination bucket, Amazon S3 generates a unique version ID for the copied object. This version ID is different from the version ID of the source object. Amazon S3 returns the version ID of the copied object in the `x-amz-version-id` response header in the response.  
If you do not enable versioning or suspend it on the destination bucket, the version ID that Amazon S3 generates in the `x-amz-version-id` response header is always null.  
 **Directory buckets** - S3 Versioning isn't enabled and supported for directory buckets.
Pattern: `\/?.+\/.+`   
Required: Yes

 ** [x-amz-copy-source-if-match](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceIfMatch"></a>
Copies the object if its entity tag (ETag) matches the specified tag.  
 If both the `x-amz-copy-source-if-match` and `x-amz-copy-source-if-unmodified-since` headers are present in the request and evaluate as follows, Amazon S3 returns `200 OK` and copies the data:  
+  `x-amz-copy-source-if-match` condition evaluates to true
+  `x-amz-copy-source-if-unmodified-since` condition evaluates to false

 ** [x-amz-copy-source-if-modified-since](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceIfModifiedSince"></a>
Copies the object if it has been modified since the specified time.  
If both the `x-amz-copy-source-if-none-match` and `x-amz-copy-source-if-modified-since` headers are present in the request and evaluate as follows, Amazon S3 returns the `412 Precondition Failed` response code:  
+  `x-amz-copy-source-if-none-match` condition evaluates to false
+  `x-amz-copy-source-if-modified-since` condition evaluates to true

 ** [x-amz-copy-source-if-none-match](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceIfNoneMatch"></a>
Copies the object if its entity tag (ETag) is different than the specified ETag.  
If both the `x-amz-copy-source-if-none-match` and `x-amz-copy-source-if-modified-since` headers are present in the request and evaluate as follows, Amazon S3 returns the `412 Precondition Failed` response code:  
+  `x-amz-copy-source-if-none-match` condition evaluates to false
+  `x-amz-copy-source-if-modified-since` condition evaluates to true

 ** [x-amz-copy-source-if-unmodified-since](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceIfUnmodifiedSince"></a>
Copies the object if it hasn't been modified since the specified time.  
 If both the `x-amz-copy-source-if-match` and `x-amz-copy-source-if-unmodified-since` headers are present in the request and evaluate as follows, Amazon S3 returns `200 OK` and copies the data:  
+  `x-amz-copy-source-if-match` condition evaluates to true
+  `x-amz-copy-source-if-unmodified-since` condition evaluates to false

 ** [x-amz-copy-source-server-side-encryption-customer-algorithm](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceSSECustomerAlgorithm"></a>
Specifies the algorithm to use when decrypting the source object (for example, `AES256`).  
If the source object for the copy is stored in Amazon S3 using SSE-C, you must provide the necessary encryption information in your request so that Amazon S3 can decrypt the object for copying.  
This functionality is not supported when the source object is in a directory bucket.

 ** [x-amz-copy-source-server-side-encryption-customer-key](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceSSECustomerKey"></a>
Specifies the customer-provided encryption key for Amazon S3 to use to decrypt the source object. The encryption key provided in this header must be the same one that was used when the source object was created.  
If the source object for the copy is stored in Amazon S3 using SSE-C, you must provide the necessary encryption information in your request so that Amazon S3 can decrypt the object for copying.  
This functionality is not supported when the source object is in a directory bucket.

 ** [x-amz-copy-source-server-side-encryption-customer-key-MD5](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-CopySourceSSECustomerKeyMD5"></a>
Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error.  
If the source object for the copy is stored in Amazon S3 using SSE-C, you must provide the necessary encryption information in your request so that Amazon S3 can decrypt the object for copying.  
This functionality is not supported when the source object is in a directory bucket.

 ** [x-amz-expected-bucket-owner](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ExpectedBucketOwner"></a>
The account ID of the expected destination bucket owner. If the account ID that you provide does not match the actual owner of the destination bucket, the request fails with the HTTP status code `403 Forbidden` (access denied).

 ** [x-amz-grant-full-control](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-GrantFullControl"></a>
Gives the grantee READ, READ\_ACP, and WRITE\_ACP permissions on the object.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-read](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-GrantRead"></a>
Allows grantee to read the object data and its metadata.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-read-acp](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-GrantReadACP"></a>
Allows grantee to read the object ACL.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-write-acp](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-GrantWriteACP"></a>
Allows grantee to write the ACL for the applicable object.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-metadata-directive](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-MetadataDirective"></a>
Specifies whether the metadata is copied from the source object or replaced with metadata that's provided in the request. When copying an object, you can preserve all metadata (the default) or specify new metadata. If this header isn’t specified, `COPY` is the default behavior.   
 **General purpose bucket** - For general purpose buckets, when you grant permissions, you can use the `s3:x-amz-metadata-directive` condition key to enforce certain metadata behavior when objects are uploaded. For more information, see [Amazon S3 condition key examples](https://docs.aws.amazon.com/AmazonS3/latest/dev/amazon-s3-policy-keys.html) in the *Amazon S3 User Guide*.  
 `x-amz-website-redirect-location` is unique to each object and is not copied when using the `x-amz-metadata-directive` header. To copy the value, you must specify `x-amz-website-redirect-location` in the request header.
Valid Values: `COPY | REPLACE` 

 ** [x-amz-object-annotation-directive](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-AnnotationDirective"></a>
Specifies whether you want to copy annotations from the source object or exclude them. If this header isn't specified, `COPY` is the default behavior.  
Valid Values: `COPY | EXCLUDE`   
You can specify this directive as either an HTTP header (`x-amz-object-annotation-directive`) or as a query string parameter. Use the query string form when generating presigned URLs that need to control annotation copy behavior.  
When set to `COPY`, you must have `s3:GetObjectAnnotation` permission on the source object and `s3:PutObjectAnnotation` permission on the destination. Each annotation copied is billed as a separate PUT request. If annotations on the source are modified during the copy, Amazon S3 returns a retryable error.  
For directory buckets, annotations are not supported. Use `EXCLUDE` to copy objects to directory buckets without errors. If you specify `COPY` for a directory bucket, the request returns HTTP 501 (Not Implemented).
When you copy objects using multipart upload (for example, when the AWS CLI or AWS SDKs use Transfer Manager for objects larger than approximately 8 MB), annotations are not copied by default. To include annotations, specify `--copy-props default` in the AWS CLI or the equivalent SDK configuration. With this opt-in, the SDK reads source annotations, completes the multipart upload, and then writes each annotation to the destination. Between the upload completion and the last annotation write, the destination object exists without all its annotations.
Valid Values: `COPY | EXCLUDE` 

 ** [x-amz-object-lock-event-hold](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockEventHold"></a>
The event hold status to apply to the object copy. Set to `ON` to enable or `OFF` to disable.  
This functionality is not supported for directory buckets.
Valid Values: `ON | OFF` 

 ** [x-amz-object-lock-event-hold-duration-days](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockEventHoldDurationDays"></a>
The event hold duration in days to apply to the object copy. You cannot specify a duration in both days and years.  
This functionality is not supported for directory buckets.

 ** [x-amz-object-lock-event-hold-duration-years](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockEventHoldDurationYears"></a>
The event hold duration in years to apply to the object copy. You cannot specify a duration in both days and years.  
This functionality is not supported for directory buckets.

 ** [x-amz-object-lock-legal-hold](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockLegalHoldStatus"></a>
Specifies whether you want to apply a legal hold to the object copy.  
This functionality is not supported for directory buckets.
Valid Values: `ON | OFF` 

 ** [x-amz-object-lock-mode](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockMode"></a>
The Object Lock mode that you want to apply to the object copy.  
This functionality is not supported for directory buckets.
Valid Values: `GOVERNANCE | COMPLIANCE` 

 ** [x-amz-object-lock-retain-until-date](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ObjectLockRetainUntilDate"></a>
The date and time when you want the Object Lock of the object copy to expire.  
This functionality is not supported for directory buckets.

 ** [x-amz-request-payer](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-RequestPayer"></a>
Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for the corresponding charges. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-server-side-encryption](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ServerSideEncryption"></a>
The server-side encryption algorithm used when storing this object in Amazon S3. Unrecognized or unsupported values won’t write a destination object and will receive a `400 Bad Request` response.   
Amazon S3 automatically encrypts all new objects that are copied to an S3 bucket. When copying an object, if you don't specify encryption information in your copy request, the encryption setting of the target object is set to the default encryption configuration of the destination bucket. By default, all buckets have a base level of encryption configuration that uses server-side encryption with Amazon S3 managed keys (SSE-S3). If the destination bucket has a different default encryption configuration, Amazon S3 uses the corresponding encryption key to encrypt the target object copy.  
With server-side encryption, Amazon S3 encrypts your data as it writes your data to disks in its data centers and decrypts the data when you access it. For more information about server-side encryption, see [Using Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/dev/serv-side-encryption.html) in the *Amazon S3 User Guide*.  
 **General purpose buckets **   
+ For general purpose buckets, there are the following supported options for server-side encryption: server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS), dual-layer server-side encryption with AWS KMS keys (DSSE-KMS), and server-side encryption with customer-provided encryption keys (SSE-C). Amazon S3 uses the corresponding KMS key, or a customer-provided key to encrypt the target object copy.
+ When you perform a `CopyObject` operation, if you want to use a different type of encryption setting for the target object, you can specify appropriate encryption-related headers to encrypt the target object with an Amazon S3 managed key, a KMS key, or a customer-provided key. If the encryption setting in your request is different from the default encryption configuration of the destination bucket, the encryption setting in your request takes precedence. 
 **Directory buckets **   
+ For directory buckets, there are only two supported options for server-side encryption: server-side encryption with Amazon S3 managed keys (SSE-S3) (`AES256`) and server-side encryption with AWS KMS keys (SSE-KMS) (`aws:kms`). We recommend that the bucket's default encryption uses the desired encryption configuration and you don't override the bucket default encryption in your `CreateSession` requests or `PUT` object requests. Then, new objects are automatically encrypted with the desired encryption settings. For more information, see [Protecting data with server-side encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-serv-side-encryption.html) in the *Amazon S3 User Guide*. For more information about the encryption overriding behaviors in directory buckets, see [Specifying server-side encryption with AWS KMS for new object uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-specifying-kms-encryption.html).
+ To encrypt new object copies to a directory bucket with SSE-KMS, we recommend you specify SSE-KMS as the directory bucket's default encryption configuration with a KMS key (specifically, a [customer managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk)). The [AWS managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#aws-managed-cmk) (`aws/s3`) isn't supported. Your SSE-KMS configuration can only support 1 [customer managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk) per directory bucket for the lifetime of the bucket. After you specify a customer managed key for SSE-KMS, you can't override the customer managed key for the bucket's SSE-KMS configuration. Then, when you perform a `CopyObject` operation and want to specify server-side encryption settings for new object copies with SSE-KMS in the encryption-related request headers, you must ensure the encryption key is the same customer managed key that you specified for the directory bucket's default encryption configuration. 
+  **S3 access points for Amazon FSx ** - When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is `aws:fsx`. All Amazon FSx file systems have encryption configured by default and are encrypted at rest. Data is automatically encrypted before being written to the file system, and automatically decrypted as it is read. These processes are handled transparently by Amazon FSx.
Valid Values: `AES256 | aws:fsx | aws:backup | aws:kms | aws:kms:dsse` 

 ** [x-amz-server-side-encryption-aws-kms-key-id](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-SSEKMSKeyId"></a>
Specifies the AWS KMS key ID (Key ID, Key ARN, or Key Alias) to use for object encryption. All GET and PUT requests for an object protected by AWS KMS will fail if they're not made via SSL or using SigV4. For information about configuring any of the officially supported AWS SDKs and AWS CLI, see [Specifying the Signature Version in Request Authentication](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingAWSSDK.html#specify-signature-version) in the *Amazon S3 User Guide*.  
 **Directory buckets** - To encrypt data using SSE-KMS, it's recommended to specify the `x-amz-server-side-encryption` header to `aws:kms`. Then, the `x-amz-server-side-encryption-aws-kms-key-id` header implicitly uses the bucket's default KMS customer managed key ID. If you want to explicitly set the ` x-amz-server-side-encryption-aws-kms-key-id` header, it must match the bucket's default customer managed key (using key ID or ARN, not alias). Your SSE-KMS configuration can only support 1 [customer managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk) per directory bucket's lifetime. The [AWS managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#aws-managed-cmk) (`aws/s3`) isn't supported. Incorrect key specification results in an HTTP `400 Bad Request` error. 

 ** [x-amz-server-side-encryption-bucket-key-enabled](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-BucketKeyEnabled"></a>
Specifies whether Amazon S3 should use an S3 Bucket Key for object encryption with server-side encryption using AWS Key Management Service (AWS KMS) keys (SSE-KMS). If a target object uses SSE-KMS, you can enable an S3 Bucket Key for the object.  
Setting this header to `true` causes Amazon S3 to use an S3 Bucket Key for object encryption with SSE-KMS. Specifying this header with a COPY action doesn’t affect bucket-level settings for S3 Bucket Key.  
For more information, see [Amazon S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/dev/bucket-key.html) in the *Amazon S3 User Guide*.  
 **Directory buckets** - S3 Bucket Keys aren't supported, when you copy SSE-KMS encrypted objects from general purpose buckets to directory buckets, from directory buckets to general purpose buckets, or between directory buckets, through [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html). In this case, Amazon S3 makes a call to AWS KMS every time a copy request is made for a KMS-encrypted object.

 ** [x-amz-server-side-encryption-context](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-SSEKMSEncryptionContext"></a>
Specifies the AWS KMS Encryption Context as an additional encryption context to use for the destination object encryption. The value of this header is a base64-encoded UTF-8 string holding JSON with the encryption context key-value pairs.  
 **General purpose buckets** - This value must be explicitly added to specify encryption context for `CopyObject` requests if you want an additional encryption context for your destination object. The additional encryption context of the source object won't be copied to the destination object. For more information, see [Encryption context](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html#encryption-context) in the *Amazon S3 User Guide*.  
 **Directory buckets** - You can optionally provide an explicit encryption context value. The value must match the default encryption context - the bucket Amazon Resource Name (ARN). An additional encryption context value is not supported. 

 ** [x-amz-server-side-encryption-customer-algorithm](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-SSECustomerAlgorithm"></a>
Specifies the algorithm to use when encrypting the object (for example, `AES256`).  
When you perform a `CopyObject` operation, if you want to use a different type of encryption setting for the target object, you can specify appropriate encryption-related headers to encrypt the target object with an Amazon S3 managed key, a KMS key, or a customer-provided key. If the encryption setting in your request is different from the default encryption configuration of the destination bucket, the encryption setting in your request takes precedence.   
This functionality is not supported when the destination bucket is a directory bucket.

 ** [x-amz-server-side-encryption-customer-key](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-SSECustomerKey"></a>
Specifies the customer-provided encryption key for Amazon S3 to use in encrypting data. This value is used to store the object and then it is discarded. Amazon S3 does not store the encryption key. The key must be appropriate for use with the algorithm specified in the `x-amz-server-side-encryption-customer-algorithm` header.  
This functionality is not supported when the destination bucket is a directory bucket.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-SSECustomerKeyMD5"></a>
Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error.  
This functionality is not supported when the destination bucket is a directory bucket.

 ** [x-amz-source-expected-bucket-owner](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-ExpectedSourceBucketOwner"></a>
The account ID of the expected source bucket owner. If the account ID that you provide does not match the actual owner of the source bucket, the request fails with the HTTP status code `403 Forbidden` (access denied).

 ** [x-amz-storage-class](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-StorageClass"></a>
If the `x-amz-storage-class` header is not used, the copied object will be stored in the `STANDARD` Storage Class by default. The `STANDARD` storage class provides high durability and high availability. Depending on performance needs, you can specify a different Storage Class.   
+  **Directory buckets ** - Directory buckets only support `EXPRESS_ONEZONE` (the S3 Express One Zone storage class) in Availability Zones and `ONEZONE_IA` (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones. Unsupported storage class values won't write a destination object and will respond with the HTTP status code `400 Bad Request`.
+  **Amazon S3 on Outposts ** - S3 on Outposts only uses the `OUTPOSTS` Storage Class.
You can use the `CopyObject` action to change the storage class of an object that is already stored in Amazon S3 by using the `x-amz-storage-class` header. For more information, see [Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/dev/storage-class-intro.html) in the *Amazon S3 User Guide*.  
Before using an object as a source object for the copy operation, you must restore a copy of it if it meets any of the following conditions:  
+ The storage class of the source object is `GLACIER` or `DEEP_ARCHIVE`.
+ The storage class of the source object is `INTELLIGENT_TIERING` and it's [S3 Intelligent-Tiering access tier](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html#intel-tiering-tier-definition) is `Archive Access` or `Deep Archive Access`.
For more information, see [RestoreObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_RestoreObject.html) and [Copying Objects](https://docs.aws.amazon.com/AmazonS3/latest/dev/CopyingObjectsExamples.html) in the *Amazon S3 User Guide*.  
Valid Values: `STANDARD | REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE | OUTPOSTS | GLACIER_IR | SNOW | EXPRESS_ONEZONE | FSX_OPENZFS | FSX_ONTAP | AWS_BACKUP_WARM | AWS_BACKUP_LOW_COST_WARM` 

 ** [x-amz-tagging](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-Tagging"></a>
The tag-set for the object copy in the destination bucket. This value must be used in conjunction with the `x-amz-tagging-directive` if you choose `REPLACE` for the `x-amz-tagging-directive`. If you choose `COPY` for the `x-amz-tagging-directive`, you don't need to set the `x-amz-tagging` header, because the tag-set will be copied from the source object directly. The tag-set must be encoded as URL Query parameters.  
The default value is the empty value.  
 **Directory buckets** - For directory buckets in a `CopyObject` operation, only the empty tag-set is supported. Any requests that attempt to write non-empty tags into directory buckets will receive a `501 Not Implemented` status code. When the destination bucket is a directory bucket, you will receive a `501 Not Implemented` response in any of the following situations:  
+ When you attempt to `COPY` the tag-set from an S3 source object that has non-empty tags.
+ When you attempt to `REPLACE` the tag-set of a source object and set a non-empty value to `x-amz-tagging`.
+ When you don't set the `x-amz-tagging-directive` header and the source object has non-empty tags. This is because the default value of `x-amz-tagging-directive` is `COPY`.
Because only the empty tag-set is supported for directory buckets in a `CopyObject` operation, the following situations are allowed:  
+ When you attempt to `COPY` the tag-set from a directory bucket source object that has no tags to a general purpose bucket. It copies an empty tag-set to the destination object.
+ When you attempt to `REPLACE` the tag-set of a directory bucket source object and set the `x-amz-tagging` value of the directory bucket destination object to empty.
+ When you attempt to `REPLACE` the tag-set of a general purpose bucket source object that has non-empty tags and set the `x-amz-tagging` value of the directory bucket destination object to empty.
+ When you attempt to `REPLACE` the tag-set of a directory bucket source object and don't set the `x-amz-tagging` value of the directory bucket destination object. This is because the default value of `x-amz-tagging` is the empty value.

 ** [x-amz-tagging-directive](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-TaggingDirective"></a>
Specifies whether the object tag-set is copied from the source object or replaced with the tag-set that's provided in the request.  
The default value is `COPY`.  
 **Directory buckets** - For directory buckets in a `CopyObject` operation, only the empty tag-set is supported. Any requests that attempt to write non-empty tags into directory buckets will receive a `501 Not Implemented` status code. When the destination bucket is a directory bucket, you will receive a `501 Not Implemented` response in any of the following situations:  
+ When you attempt to `COPY` the tag-set from an S3 source object that has non-empty tags.
+ When you attempt to `REPLACE` the tag-set of a source object and set a non-empty value to `x-amz-tagging`.
+ When you don't set the `x-amz-tagging-directive` header and the source object has non-empty tags. This is because the default value of `x-amz-tagging-directive` is `COPY`.
Because only the empty tag-set is supported for directory buckets in a `CopyObject` operation, the following situations are allowed:  
+ When you attempt to `COPY` the tag-set from a directory bucket source object that has no tags to a general purpose bucket. It copies an empty tag-set to the destination object.
+ When you attempt to `REPLACE` the tag-set of a directory bucket source object and set the `x-amz-tagging` value of the directory bucket destination object to empty.
+ When you attempt to `REPLACE` the tag-set of a general purpose bucket source object that has non-empty tags and set the `x-amz-tagging` value of the directory bucket destination object to empty.
+ When you attempt to `REPLACE` the tag-set of a directory bucket source object and don't set the `x-amz-tagging` value of the directory bucket destination object. This is because the default value of `x-amz-tagging` is the empty value.
Valid Values: `COPY | REPLACE` 

 ** [x-amz-website-redirect-location](#API_CopyObject_RequestSyntax) **   <a name="AmazonS3-CopyObject-request-header-WebsiteRedirectLocation"></a>
If the destination bucket is configured as a website, redirects requests for this object copy to another object in the same bucket or to an external URL. Amazon S3 stores the value of this header in the object metadata. This value is unique to each object and is not copied when using the `x-amz-metadata-directive` header. Instead, you may opt to provide this header in combination with the `x-amz-metadata-directive` header.  
This functionality is not supported for directory buckets.

## Request Body
<a name="API_CopyObject_RequestBody"></a>

The request does not have a request body.

## Response Syntax
<a name="API_CopyObject_ResponseSyntax"></a>

```
HTTP/1.1 200
x-amz-expiration: {{Expiration}}
x-amz-copy-source-version-id: {{CopySourceVersionId}}
x-amz-version-id: {{VersionId}}
x-amz-server-side-encryption: {{ServerSideEncryption}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-server-side-encryption-aws-kms-key-id: {{SSEKMSKeyId}}
x-amz-server-side-encryption-context: {{SSEKMSEncryptionContext}}
x-amz-server-side-encryption-bucket-key-enabled: {{BucketKeyEnabled}}
x-amz-request-charged: {{RequestCharged}}
<?xml version="1.0" encoding="UTF-8"?>
<CopyObjectResult>
   <ETag>string</ETag>
   <LastModified>timestamp</LastModified>
   <ChecksumType>string</ChecksumType>
   <ChecksumCRC32>string</ChecksumCRC32>
   <ChecksumCRC32C>string</ChecksumCRC32C>
   <ChecksumCRC64NVME>string</ChecksumCRC64NVME>
   <ChecksumSHA1>string</ChecksumSHA1>
   <ChecksumSHA256>string</ChecksumSHA256>
   <ChecksumSHA512>string</ChecksumSHA512>
   <ChecksumMD5>string</ChecksumMD5>
   <ChecksumXXHASH64>string</ChecksumXXHASH64>
   <ChecksumXXHASH3>string</ChecksumXXHASH3>
   <ChecksumXXHASH128>string</ChecksumXXHASH128>
</CopyObjectResult>
```

## Response Elements
<a name="API_CopyObject_ResponseElements"></a>

If the action is successful, the service sends back an HTTP 200 response.

The response returns the following HTTP headers.

 ** [x-amz-copy-source-version-id](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-CopySourceVersionId"></a>
Version ID of the source object that was copied.  
This functionality is not supported when the source object is in a directory bucket.

 ** [x-amz-expiration](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-Expiration"></a>
If the object expiration is configured, the response includes this header.  
Object expiration information is not returned in directory buckets and this header returns the value "`NotImplemented`" in all responses for directory buckets.

 ** [x-amz-request-charged](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-RequestCharged"></a>
If present, indicates that the requester was successfully charged for the request. For more information, see [Using Requester Pays buckets for storage transfers and usage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html) in the *Amazon Simple Storage Service user guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-server-side-encryption](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-ServerSideEncryption"></a>
The server-side encryption algorithm used when you store this object in Amazon S3 or Amazon FSx.  
When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is `aws:fsx`.
Valid Values: `AES256 | aws:fsx | aws:backup | aws:kms | aws:kms:dsse` 

 ** [x-amz-server-side-encryption-aws-kms-key-id](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-SSEKMSKeyId"></a>
If present, indicates the ID of the KMS key that was used for object encryption.

 ** [x-amz-server-side-encryption-bucket-key-enabled](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-BucketKeyEnabled"></a>
Indicates whether the copied object uses an S3 Bucket Key for server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS).

 ** [x-amz-server-side-encryption-context](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-SSEKMSEncryptionContext"></a>
If present, indicates the AWS KMS Encryption Context to use for object encryption. The value of this header is a Base64 encoded UTF-8 string holding JSON with the encryption context key-value pairs.

 ** [x-amz-server-side-encryption-customer-algorithm](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-SSECustomerAlgorithm"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to confirm the encryption algorithm that's used.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-SSECustomerKeyMD5"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to provide the round-trip message integrity verification of the customer-provided encryption key.  
This functionality is not supported for directory buckets.

 ** [x-amz-version-id](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-header-VersionId"></a>
Version ID of the newly created copy.  
This functionality is not supported for directory buckets.

The following data is returned in XML format by the service.

 ** [CopyObjectResult](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-CopyObjectResult"></a>
Root level tag for the CopyObjectResult parameters.  
Required: Yes

 ** [ChecksumCRC32](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32` checksum of the object. This checksum is only present if the checksum was uploaded with the object. For more information, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumCRC32C](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the object. This checksum is only present if the checksum was uploaded with the object. For more information, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumCRC64NVME](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the object. This checksum is present if the object being copied was uploaded with the `CRC64NVME` checksum algorithm, or if the object was uploaded without a checksum (and Amazon S3 added the default checksum, `CRC64NVME`, to the uploaded object). For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumMD5](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` digest of the object. This checksum is only present if the object was uploaded with the `MD5` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumSHA1](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` digest of the object. This checksum is only present if the checksum was uploaded with the object. For more information, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumSHA256](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` digest of the object. This checksum is only present if the checksum was uploaded with the object. For more information, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumSHA512](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` digest of the object. This checksum is only present if the object was uploaded with the `SHA512` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumType](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumType"></a>
The checksum type that is used to calculate the object’s checksum value. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String  
Valid Values: `COMPOSITE | FULL_OBJECT` 

 ** [ChecksumXXHASH128](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the object. This checksum is only present if the object was uploaded with the `XXHASH128` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumXXHASH3](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the object. This checksum is only present if the object was uploaded with the `XXHASH3` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ChecksumXXHASH64](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the object. This checksum is only present if the object was uploaded with the `XXHASH64` checksum algorithm. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Type: String

 ** [ETag](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-ETag"></a>
Returns the ETag of the new object. The ETag reflects only changes to the contents of an object, not its metadata.  
Type: String

 ** [LastModified](#API_CopyObject_ResponseSyntax) **   <a name="AmazonS3-CopyObject-response-LastModified"></a>
Creation date of the object.  
Type: Timestamp

## Errors
<a name="API_CopyObject_Errors"></a>

 ** ObjectNotInActiveTierError **   
The source object of the COPY action is not in the active tier and is only stored in Amazon S3 Glacier.  
HTTP Status Code: 403

## Examples
<a name="API_CopyObject_Examples"></a>

### Sample Request for general purpose buckets
<a name="API_CopyObject_Example_1"></a>

This example copies `my-image.jpg` into the `amzn-s3-demo-bucket` bucket, with the key name `my-second-image.jpg`.

```
                PUT /my-second-image.jpg HTTP/1.1
                Host: amzn-s3-demo-bucket.s3.<Region>.amazonaws.com
                Date: Wed, 28 Oct 2009 22:32:00 GMT
                x-amz-copy-source: /amzn-s3-demo-bucket/my-image.jpg
                Authorization: authorization string
```

### Sample Response for general purpose buckets
<a name="API_CopyObject_Example_2"></a>

This example illustrates one usage of CopyObject.

```
               HTTP/1.1 200 OK
               x-amz-id-2: eftixk72aD6Ap51TnqcoF8eFidJG9Z/2mkiDFu8yU9AS1ed4OpIszj7UDNEHGran
               x-amz-request-id: 318BC8BC148832E5
               x-amz-copy-source-version-id: 3/L4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY+MTRCxf3vjVBH40Nr8X8gdRQBpUMLUo
               x-amz-version-id: QUpfdndhfd8438MNFDN93jdnJFkdmqnh893
               Date: Wed, 28 Oct 2009 22:32:00 GMT
               Connection: close
               Server: AmazonS3

               <CopyObjectResult>
                  <LastModified>2009-10-12T17:50:30.000Z</LastModified>
                  <ETag>"9b2cf535f27731c974343645a3985328"</ETag>
               </CopyObjectResult>
```

### Sample Request for general purpose buckets: Copying a specified version of an object
<a name="API_CopyObject_Example_3"></a>

The following request copies the `my-image.jpg` key with the specified version ID, copies it into the `amzn-s3-demo-bucket` bucket, and gives it the `my-second-image.jpg` key.

```
                PUT /my-second-image.jpg HTTP/1.1
                Host: amzn-s3-demo-bucket.s3.<Region>.amazonaws.com
                Date: Wed, 28 Oct 2009 22:32:00 GMT
                x-amz-copy-source: /amzn-s3-demo-bucket/my-image.jpg?versionId=3/L4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY+MTRCxf3vjVBH40Nr8X8gdRQBpUMLUo
                Authorization: authorization string
```

### Success Response for general purpose buckets: Copying a versioned object into a version-enabled bucket
<a name="API_CopyObject_Example_4"></a>

The following response shows that an object was copied into a target bucket where versioning is enabled.

```
                HTTP/1.1 200 OK
                x-amz-id-2: eftixk72aD6Ap51TnqcoF8eFidJG9Z/2mkiDFu8yU9AS1ed4OpIszj7UDNEHGran
                x-amz-request-id: 318BC8BC148832E5
                x-amz-version-id: QUpfdndhfd8438MNFDN93jdnJFkdmqnh893
                x-amz-copy-source-version-id: 09df8234529fjs0dfi0w52935029wefdj
                Date: Wed, 28 Oct 2009 22:32:00 GMT
                Connection: close
                Server: AmazonS3
 
                <?xml version="1.0" encoding="UTF-8"?>
                <CopyObjectResult>
                  <LastModified>2009-10-12T17:50:30.000Z</LastModified>
                  <ETag>"9b2cf535f27731c974343645a3985328"</ETag>
                </CopyObjectResult>
```

### Success Response for general purpose buckets: Copying a versioned object into a version-suspended bucket
<a name="API_CopyObject_Example_5"></a>

The following response shows that an object was copied into a target bucket where versioning is suspended. The parameter `VersionId` does not appear.

```
               HTTP/1.1 200 OK
               x-amz-id-2: eftixk72aD6Ap51TnqcoF8eFidJG9Z/2mkiDFu8yU9AS1ed4OpIszj7UDNEHGran
               x-amz-request-id: 318BC8BC148832E5
               x-amz-copy-source-version-id: 3/L4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY+MTRCxf3vjVBH40Nr8X8gdRQBpUMLUo
               Date: Wed, 28 Oct 2009 22:32:00 GMT
               Connection: close
               Server: AmazonS3

               <?xml version="1.0" encoding="UTF-8"?>
                <CopyObjectResult>
                  <LastModified>2009-10-28T22:32:00</LastModified>
                  <ETag>"9b2cf535f27731c974343645a3985328"</ETag>
                </CopyObjectResult>
```

### Sample Request for general purpose buckets: Copy from unencrypted object to an object encrypted with server-side encryption with customer-provided encryption keys
<a name="API_CopyObject_Example_6"></a>

The following example specifies the HTTP PUT header to copy an unencrypted object to an object encrypted with server-side encryption with customer-provided encryption keys (SSE-C).

```
                PUT /exampleDestinationObject HTTP/1.1
                Host: amzn-s3-demo-destination-bucket.s3.<Region>.amazonaws.com	
                x-amz-server-side-encryption-customer-algorithm: AES256
                x-amz-server-side-encryption-customer-key: Base64(YourKey)
                x-amz-server-side-encryption-customer-key-MD5 : Base64(MD5(YourKey))
                x-amz-metadata-directive: metadata_directive
                x-amz-copy-source: /amzn-s3-demo-source-bucket/exampleSourceObject
                x-amz-copy-source-if-match: etag
                x-amz-copy-source-if-none-match: etag
                x-amz-copy-source-if-unmodified-since: time_stamp
                x-amz-copy-source-if-modified-since: time_stamp
                
               <request metadata>
                Authorization: authorization string (see Authenticating Requests (AWS Signature Version 4))
                Date: date
```

### Sample Request for general purpose buckets: Copy from an object encrypted with SSE-C to an object encrypted with SSE-C
<a name="API_CopyObject_Example_7"></a>

The following example specifies the HTTP PUT header to copy an object encrypted with server-side encryption with customer-provided encryption keys to an object encrypted with server-side encryption with customer-provided encryption keys for key rotation.

**Note**  
If you have server-side encryption with customer-provided keys (SSE-C) blocked for your general purpose bucket, you will get an HTTP 403 Access Denied error when you specify the SSE-C request headers while writing new data to your bucket. For more information, see [Blocking or unblocking SSE-C for a general purpose bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/blocking-unblocking-s3-c-encryption-gpb.html).

```
                PUT /exampleDestinationObject HTTP/1.1
                Host: amzn-s3-demo-destination-bucket.s3.<Region>.amazonaws.com	
                x-amz-server-side-encryption-customer-algorithm: AES256
                x-amz-server-side-encryption-customer-key: Base64(NewKey)
                x-amz-server-side-encryption-customer-key-MD5: Base64(MD5(NewKey))
                x-amz-metadata-directive: metadata_directive
                x-amz-copy-source: /amzn-s3-demo-source-bucket/sourceObject
                x-amz-copy-source-if-match: etag
                x-amz-copy-source-if-none-match: etag
                x-amz-copy-source-if-unmodified-since: time_stamp
                x-amz-copy-source-if-modified-since: time_stamp
                x-amz-copy-source-server-side-encryption-customer-algorithm: AES256
                x-amz-copy-source-server-side-encryption-customer-key: Base64(OldKey)
                x-amz-copy-source-server-side-encryption-customer-key-MD5: Base64(MD5(OldKey))
                
               <request metadata>
                Authorization: authorization string (see Authenticating Requests (AWS Signature Version 4))
                Date: date
```

## See Also
<a name="API_CopyObject_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS Command Line Interface V2](https://docs.aws.amazon.com/goto/cli2/s3-2006-03-01/CopyObject) 
+  [AWS SDK for .NET V4](https://docs.aws.amazon.com/goto/DotNetSDKV4/s3-2006-03-01/CopyObject) 
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/CopyObject) 
+  [AWS SDK for Go v2](https://docs.aws.amazon.com/goto/SdkForGoV2/s3-2006-03-01/CopyObject) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/CopyObject) 
+  [AWS SDK for JavaScript V3](https://docs.aws.amazon.com/goto/SdkForJavaScriptV3/s3-2006-03-01/CopyObject) 
+  [AWS SDK for Kotlin](https://docs.aws.amazon.com/goto/SdkForKotlin/s3-2006-03-01/CopyObject) 
+  [AWS SDK for PHP V3](https://docs.aws.amazon.com/goto/SdkForPHPV3/s3-2006-03-01/CopyObject) 
+  [AWS SDK for Python (Boto3)](https://docs.aws.amazon.com/goto/boto3/s3-2006-03-01/CopyObject) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/CopyObject) 