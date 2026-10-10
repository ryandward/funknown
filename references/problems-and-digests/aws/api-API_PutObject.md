

# PutObject
<a name="API_PutObject"></a>

**Important**  
End of support notice: As of October 1, 2025, Amazon S3 has discontinued support for Email Grantee Access Control Lists (ACLs). If you attempt to use an Email Grantee ACL in a request after October 1, 2025, the request will receive an `HTTP 405` (Method Not Allowed) error.  
This change affects the following AWS Regions: US East (N. Virginia), US West (N. California), US West (Oregon), Asia Pacific (Singapore), Asia Pacific (Sydney), Asia Pacific (Tokyo), Europe (Ireland), and South America (São Paulo).

Adds an object to a bucket.

**Note**  
Amazon S3 never adds partial objects; if you receive a success response, Amazon S3 added the entire object to the bucket. You cannot use `PutObject` to only update a single piece of metadata for an existing object. You must put the entire object with updated metadata if you want to update some values.
If your bucket uses the bucket owner enforced setting for Object Ownership, ACLs are disabled and no longer affect permissions. All objects written to the bucket by any account will be owned by the bucket owner.
 **Directory buckets** - For directory buckets, you must make requests for this API operation to the Zonal endpoint. These endpoints support virtual-hosted-style requests in the format `https://amzn-s3-demo-bucket.s3express-zone-id.region-code.amazonaws.com/key-name `. Path-style requests are not supported. For more information about endpoints in Availability Zones, see [Regional and Zonal endpoints for directory buckets in Availability Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/endpoint-directory-buckets-AZ.html) in the *Amazon S3 User Guide*. For more information about endpoints in Local Zones, see [Concepts for directory buckets in Local Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-lzs-for-directory-buckets.html) in the *Amazon S3 User Guide*.

Amazon S3 is a distributed system. If it receives multiple write requests for the same object simultaneously, it overwrites all but the last object written. However, Amazon S3 provides features that can modify this behavior:
+  **S3 Object Lock** - To prevent objects from being deleted or overwritten, you can use [Amazon S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html) in the *Amazon S3 User Guide*.
**Note**  
This functionality is not supported for directory buckets.
+  **If-None-Match** - Uploads the object only if the object key name does not already exist in the specified bucket. Otherwise, Amazon S3 returns a `412 Precondition Failed` error. If a conflicting operation occurs during the upload, S3 returns a `409 ConditionalRequestConflict` response. On a 409 failure, retry the upload.

  Expects the \* character (asterisk).

  For more information, see [Add preconditions to S3 operations with conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) in the *Amazon S3 User Guide* or [RFC 7232](https://datatracker.ietf.org/doc/rfc7232/). 
**Note**  
This functionality is not supported for S3 on Outposts.
+  **S3 Versioning** - When you enable versioning for a bucket, if Amazon S3 receives multiple write requests for the same object simultaneously, it stores all versions of the objects. For each write request that is made to the same object, Amazon S3 automatically generates a unique version ID of that object being stored in Amazon S3. You can retrieve, replace, or delete any version of the object. For more information about versioning, see [Adding Objects to Versioning-Enabled Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/AddingObjectstoVersioningEnabledBuckets.html) in the *Amazon S3 User Guide*. For information about returning the versioning state of a bucket, see [GetBucketVersioning](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetBucketVersioning.html). 
**Note**  
This functionality is not supported for directory buckets.

Permissions  
+  **General purpose bucket permissions** - The following permissions are required in your policies when your `PutObject` request includes specific headers.
  +  ** `s3:PutObject` ** - To successfully complete the `PutObject` request, you must always have the `s3:PutObject` permission on a bucket to add an object to it.
  +  ** `s3:PutObjectAcl` ** - To successfully change the objects ACL of your `PutObject` request, you must have the `s3:PutObjectAcl`.
  +  ** `s3:PutObjectTagging` ** - To successfully set the tag-set with your `PutObject` request, you must have the `s3:PutObjectTagging`.
+  **Directory bucket permissions** - To grant access to this API operation on a directory bucket, we recommend that you use the [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html) API operation for session-based authorization. Specifically, you grant the `s3express:CreateSession` permission to the directory bucket in a bucket policy or an IAM identity-based policy. Then, you make the `CreateSession` API call on the bucket to obtain a session token. With the session token in your request header, you can make API requests to this operation. After the session token expires, you make another `CreateSession` API call to generate a new session token for use. AWS CLI or SDKs create session and refresh the session token automatically to avoid service interruptions when a session expires. For more information about authorization, see [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html).

  If the object is encrypted with SSE-KMS, you must also have the `kms:GenerateDataKey` and `kms:Decrypt` permissions in IAM identity-based policies and AWS KMS key policies for the AWS KMS key.

Data integrity with Content-MD5  
+  **General purpose bucket** - To ensure that data is not corrupted traversing the network, use the `Content-MD5` header. When you use this header, Amazon S3 checks the object against the provided MD5 value and, if they do not match, Amazon S3 returns an error. Alternatively, when the object's ETag is its MD5 digest, you can calculate the MD5 while putting the object to Amazon S3 and compare the returned ETag to the calculated MD5 value.
+  **Directory bucket** - This functionality is not supported for directory buckets.

HTTP Host header syntax  
 **Directory buckets ** - The HTTP Host header syntax is ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`.

Errors  
+ You might receive an `InvalidRequest` error for several reasons. Depending on the reason for the error, you might receive one of the following messages:
  + Cannot specify both a write offset value and user-defined object metadata for existing objects.
  + Checksum Type mismatch occurred, expected checksum Type: sha1, actual checksum Type: crc32c.
  + Request body cannot be empty when 'write offset' is specified.

For more information about related Amazon S3 APIs, see the following:
+  [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html) 
+  [DeleteObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObject.html) 

**Important**  
You must URL encode any signed header values that contain spaces. For example, if your header value is `my file.txt`, containing two spaces after `my`, you must URL encode this value to `my%20%20file.txt`.

## Request Syntax
<a name="API_PutObject_RequestSyntax"></a>

```
PUT /{{Key+}} HTTP/1.1
Host: {{Bucket}}.s3.amazonaws.com
x-amz-acl: {{ACL}}
Cache-Control: {{CacheControl}}
Content-Disposition: {{ContentDisposition}}
Content-Encoding: {{ContentEncoding}}
Content-Language: {{ContentLanguage}}
Content-Length: {{ContentLength}}
Content-MD5: {{ContentMD5}}
Content-Type: {{ContentType}}
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
Expires: {{Expires}}
If-Match: {{IfMatch}}
If-None-Match: {{IfNoneMatch}}
x-amz-grant-full-control: {{GrantFullControl}}
x-amz-grant-read: {{GrantRead}}
x-amz-grant-read-acp: {{GrantReadACP}}
x-amz-grant-write-acp: {{GrantWriteACP}}
x-amz-write-offset-bytes: {{WriteOffsetBytes}}
x-amz-server-side-encryption: {{ServerSideEncryption}}
x-amz-storage-class: {{StorageClass}}
x-amz-website-redirect-location: {{WebsiteRedirectLocation}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key: {{SSECustomerKey}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-server-side-encryption-aws-kms-key-id: {{SSEKMSKeyId}}
x-amz-server-side-encryption-context: {{SSEKMSEncryptionContext}}
x-amz-server-side-encryption-bucket-key-enabled: {{BucketKeyEnabled}}
x-amz-request-payer: {{RequestPayer}}
x-amz-tagging: {{Tagging}}
x-amz-object-lock-mode: {{ObjectLockMode}}
x-amz-object-lock-retain-until-date: {{ObjectLockRetainUntilDate}}
x-amz-object-lock-legal-hold: {{ObjectLockLegalHoldStatus}}
x-amz-object-lock-event-hold: {{ObjectLockEventHold}}
x-amz-object-lock-event-hold-duration-days: {{ObjectLockEventHoldDurationDays}}
x-amz-object-lock-event-hold-duration-years: {{ObjectLockEventHoldDurationYears}}
x-amz-expected-bucket-owner: {{ExpectedBucketOwner}}

{{Body}}
```

## URI Request Parameters
<a name="API_PutObject_RequestParameters"></a>

The request uses the following URI parameters.

 ** [Bucket](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-Bucket"></a>
The bucket name to which the PUT action was initiated.   
 **Directory buckets** - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format ` bucket-base-name--zone-id--x-s3` (for example, ` amzn-s3-demo-bucket--usw2-az1--x-s3`). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the *Amazon S3 User Guide*.  
 **Access points** - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form *AccessPointName*-*AccountId*.s3-accesspoint.*Region*.amazonaws.com. When using this action with an access point through the AWS SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the *Amazon S3 User Guide*.  
Object Lambda access points are not supported by directory buckets.
 **S3 on Outposts** - When you use this action with S3 on Outposts, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form ` AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com`. When you use this action with S3 on Outposts, the destination bucket must be the Outposts access point ARN or the access point alias. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the *Amazon S3 User Guide*.  
Required: Yes

 ** [Cache-Control](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-CacheControl"></a>
Can be used to specify caching behavior along the request/reply chain. For more information, see [http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html\#sec14.9](http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9).

 ** [Content-Disposition](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentDisposition"></a>
Specifies presentational information for the object. For more information, see [https://www.rfc-editor.org/rfc/rfc6266\#section-4](https://www.rfc-editor.org/rfc/rfc6266#section-4).

 ** [Content-Encoding](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentEncoding"></a>
Specifies what content encodings have been applied to the object and thus what decoding mechanisms must be applied to obtain the media-type referenced by the Content-Type header field. For more information, see [https://www.rfc-editor.org/rfc/rfc9110.html\#field.content-encoding](https://www.rfc-editor.org/rfc/rfc9110.html#field.content-encoding).

 ** [Content-Language](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentLanguage"></a>
The language the content is in.

 ** [Content-Length](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentLength"></a>
Size of the body in bytes. This parameter is useful when the size of the body cannot be determined automatically. For more information, see [https://www.rfc-editor.org/rfc/rfc9110.html\#name-content-length](https://www.rfc-editor.org/rfc/rfc9110.html#name-content-length).

 ** [Content-MD5](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentMD5"></a>
The Base64 encoded 128-bit `MD5` digest of the message (without the headers) according to RFC 1864. This header can be used as a message integrity check to verify that the data is the same data that was originally sent. Although it is optional, we recommend using the Content-MD5 mechanism as an end-to-end integrity check. For more information about REST request authentication, see [REST Authentication](https://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html).  
The `Content-MD5` or `x-amz-sdk-checksum-algorithm` header is required for any request to upload an object with a retention period configured using Amazon S3 Object Lock. For more information, see [Uploading objects to an Object Lock enabled bucket ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html#object-lock-put-object) in the *Amazon S3 User Guide*.
This functionality is not supported for directory buckets.

 ** [Content-Type](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ContentType"></a>
A standard MIME type describing the format of the contents. For more information, see [https://www.rfc-editor.org/rfc/rfc9110.html\#name-content-type](https://www.rfc-editor.org/rfc/rfc9110.html#name-content-type).

 ** [Expires](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-Expires"></a>
The date and time at which the object is no longer cacheable. For more information, see [https://www.rfc-editor.org/rfc/rfc7234\#section-5.3](https://www.rfc-editor.org/rfc/rfc7234#section-5.3).

 ** [If-Match](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-IfMatch"></a>
Uploads the object only if the ETag (entity tag) value provided during the WRITE operation matches the ETag of the object in S3. If the ETag values do not match, the operation returns a `412 Precondition Failed` error.  
If a conflicting operation occurs during the upload S3 returns a `409 ConditionalRequestConflict` response. On a 409 failure you should fetch the object's ETag and retry the upload.  
Expects the ETag value as a string.  
For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232), or [Conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) in the *Amazon S3 User Guide*.

 ** [If-None-Match](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-IfNoneMatch"></a>
Uploads the object only if the object key name does not already exist in the bucket specified. Otherwise, Amazon S3 returns a `412 Precondition Failed` error.  
If a conflicting operation occurs during the upload S3 returns a `409 ConditionalRequestConflict` response. On a 409 failure you should retry the upload.  
Expects the '\*' (asterisk) character.  
For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232), or [Conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) in the *Amazon S3 User Guide*.

 ** [Key](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-uri-uri-Key"></a>
Object key for which the PUT action was initiated.  
Length Constraints: Minimum length of 1.  
Required: Yes

 ** [x-amz-acl](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ACL"></a>
The canned ACL to apply to the object. For more information, see [Canned ACL](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html#CannedACL) in the *Amazon S3 User Guide*.  
When adding a new object, you can use headers to grant ACL-based permissions to individual AWS accounts or to predefined groups defined by Amazon S3. These permissions are then added to the ACL on the object. By default, all objects are private. Only the owner has full access control. For more information, see [Access Control List (ACL) Overview](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html) and [Managing ACLs Using the REST API](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-using-rest-api.html) in the *Amazon S3 User Guide*.  
If the bucket that you're uploading objects to uses the bucket owner enforced setting for S3 Object Ownership, ACLs are disabled and no longer affect permissions. Buckets that use this setting only accept PUT requests that don't specify an ACL or PUT requests that specify bucket owner full control ACLs, such as the `bucket-owner-full-control` canned ACL or an equivalent form of this ACL expressed in the XML format. PUT requests that contain other ACLs (for example, custom grants to certain AWS accounts) fail and return a `400` error with the error code `AccessControlListNotSupported`. For more information, see [ Controlling ownership of objects and disabling ACLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) in the *Amazon S3 User Guide*.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.
Valid Values: `private | public-read | public-read-write | authenticated-read | aws-exec-read | bucket-owner-read | bucket-owner-full-control` 

 ** [x-amz-checksum-crc32](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumCRC32"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit `CRC32` checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc32c](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumCRC32C"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit `CRC32C` checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc64nvme](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumCRC64NVME"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `CRC64NVME` checksum of the object. The `CRC64NVME` checksum is always a full object checksum. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-md5](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumMD5"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 128-bit `MD5` digest of the object. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-sha1](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumSHA1"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 160-bit `SHA1` digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha256](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumSHA256"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 256-bit `SHA256` digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha512](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumSHA512"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 512-bit `SHA512` digest of the object. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-xxhash128](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumXXHASH128"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 128-bit `XXHASH128` checksum of the object. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-xxhash3](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumXXHASH3"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `XXHASH3` checksum of the object. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-xxhash64](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumXXHASH64"></a>
This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit `XXHASH64` checksum of the object. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-expected-bucket-owner](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ExpectedBucketOwner"></a>
The account ID of the expected bucket owner. If the account ID that you provide does not match the actual owner of the bucket, the request fails with the HTTP status code `403 Forbidden` (access denied).

 ** [x-amz-grant-full-control](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-GrantFullControl"></a>
Gives the grantee READ, READ\_ACP, and WRITE\_ACP permissions on the object.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-read](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-GrantRead"></a>
Allows grantee to read the object data and its metadata.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-read-acp](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-GrantReadACP"></a>
Allows grantee to read the object ACL.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-grant-write-acp](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-GrantWriteACP"></a>
Allows grantee to write the ACL for the applicable object.  
+ This functionality is not supported for directory buckets.
+ This functionality is not supported for Amazon S3 on Outposts.

 ** [x-amz-object-lock-event-hold](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockEventHold"></a>
Specifies the event hold status to apply to this object. Set to `ON` to enable or `OFF` to disable.  
This functionality is not supported for directory buckets.
Valid Values: `ON | OFF` 

 ** [x-amz-object-lock-event-hold-duration-days](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockEventHoldDurationDays"></a>
Specifies the event hold duration in days to apply to this object. You cannot specify a duration in both days and years.  
This functionality is not supported for directory buckets.

 ** [x-amz-object-lock-event-hold-duration-years](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockEventHoldDurationYears"></a>
Specifies the event hold duration in years to apply to this object. You cannot specify a duration in both days and years.  
This functionality is not supported for directory buckets.

 ** [x-amz-object-lock-legal-hold](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockLegalHoldStatus"></a>
Specifies whether a legal hold will be applied to this object. For more information about S3 Object Lock, see [Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/dev/object-lock.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets.
Valid Values: `ON | OFF` 

 ** [x-amz-object-lock-mode](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockMode"></a>
The Object Lock mode that you want to apply to this object.  
This functionality is not supported for directory buckets.
Valid Values: `GOVERNANCE | COMPLIANCE` 

 ** [x-amz-object-lock-retain-until-date](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ObjectLockRetainUntilDate"></a>
The date and time when you want this object's Object Lock to expire. Must be formatted as a timestamp parameter.  
This functionality is not supported for directory buckets.

 ** [x-amz-request-payer](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-RequestPayer"></a>
Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for the corresponding charges. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-sdk-checksum-algorithm](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ChecksumAlgorithm"></a>
Indicates the algorithm used to create the checksum for the object when you use the SDK. This header will not provide any additional functionality if you don't use the SDK. When you send this header, there must be a corresponding `x-amz-checksum-algorithm ` or `x-amz-trailer` header sent. Otherwise, Amazon S3 fails the request with the HTTP status code `400 Bad Request`.  
For the `x-amz-checksum-algorithm ` header, replace ` algorithm ` with the supported algorithm from the following list:   
+  `CRC32` 
+  `CRC32C` 
+  `CRC64NVME` 
+  `MD5` 
+  `SHA1` 
+  `SHA256` 
+  `SHA512` 
+  `XXHASH3` 
+  `XXHASH64` 
+  `XXHASH128` 
For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
If the individual checksum value you provide through `x-amz-checksum-algorithm ` doesn't match the checksum algorithm you set through `x-amz-sdk-checksum-algorithm`, Amazon S3 fails the request with a `BadDigest` error.  
The `Content-MD5` or `x-amz-sdk-checksum-algorithm` header is required for any request to upload an object with a retention period configured using Amazon S3 Object Lock. For more information, see [Uploading objects to an Object Lock enabled bucket ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html#object-lock-put-object) in the *Amazon S3 User Guide*.
For directory buckets, when you use AWS SDKs, `CRC32` is the default checksum algorithm that's used for performance.  
Valid Values: `CRC32 | CRC32C | SHA1 | SHA256 | CRC64NVME | SHA512 | MD5 | XXHASH64 | XXHASH3 | XXHASH128` 

 ** [x-amz-server-side-encryption](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-ServerSideEncryption"></a>
The server-side encryption algorithm that was used when you store this object in Amazon S3 or Amazon FSx.  
+  **General purpose buckets ** - You have four mutually exclusive options to protect data using server-side encryption in Amazon S3, depending on how you choose to manage the encryption keys. Specifically, the encryption key options are Amazon S3 managed keys (SSE-S3), AWS KMS keys (SSE-KMS or DSSE-KMS), and customer-provided keys (SSE-C). Amazon S3 encrypts data with server-side encryption by using Amazon S3 managed keys (SSE-S3) by default. You can optionally tell Amazon S3 to encrypt data at rest by using server-side encryption with other key options. For more information, see [Using Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html) in the *Amazon S3 User Guide*.
+  **Directory buckets ** - For directory buckets, there are only two supported options for server-side encryption: server-side encryption with Amazon S3 managed keys (SSE-S3) (`AES256`) and server-side encryption with AWS KMS keys (SSE-KMS) (`aws:kms`). We recommend that the bucket's default encryption uses the desired encryption configuration and you don't override the bucket default encryption in your `CreateSession` requests or `PUT` object requests. Then, new objects are automatically encrypted with the desired encryption settings. For more information, see [Protecting data with server-side encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-serv-side-encryption.html) in the *Amazon S3 User Guide*. For more information about the encryption overriding behaviors in directory buckets, see [Specifying server-side encryption with AWS KMS for new object uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-specifying-kms-encryption.html). 

  In the Zonal endpoint API calls (except [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html) and [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html)) using the REST API, the encryption request headers must match the encryption settings that are specified in the `CreateSession` request. You can't override the values of the encryption settings (`x-amz-server-side-encryption`, `x-amz-server-side-encryption-aws-kms-key-id`, `x-amz-server-side-encryption-context`, and `x-amz-server-side-encryption-bucket-key-enabled`) that are specified in the `CreateSession` request. You don't need to explicitly specify these encryption settings values in Zonal endpoint API calls, and Amazon S3 will use the encryption settings values from the `CreateSession` request to protect new objects in the directory bucket. 
**Note**  
When you use the CLI or the AWS SDKs, for `CreateSession`, the session token refreshes automatically to avoid service interruptions when a session expires. The CLI or the AWS SDKs use the bucket's default encryption configuration for the `CreateSession` request. It's not supported to override the encryption settings values in the `CreateSession` request. So in the Zonal endpoint API calls (except [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html) and [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html)), the encryption request headers must match the default encryption configuration of the directory bucket. 
+  **S3 access points for Amazon FSx ** - When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is `aws:fsx`. All Amazon FSx file systems have encryption configured by default and are encrypted at rest. Data is automatically encrypted before being written to the file system, and automatically decrypted as it is read. These processes are handled transparently by Amazon FSx.
Valid Values: `AES256 | aws:fsx | aws:backup | aws:kms | aws:kms:dsse` 

 ** [x-amz-server-side-encryption-aws-kms-key-id](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-SSEKMSKeyId"></a>
Specifies the AWS KMS key ID (Key ID, Key ARN, or Key Alias) to use for object encryption. If the KMS key doesn't exist in the same account that's issuing the command, you must use the full Key ARN not the Key ID.  
 **General purpose buckets** - If you specify `x-amz-server-side-encryption` with `aws:kms` or `aws:kms:dsse`, this header specifies the ID (Key ID, Key ARN, or Key Alias) of the AWS KMS key to use. If you specify `x-amz-server-side-encryption:aws:kms` or `x-amz-server-side-encryption:aws:kms:dsse`, but do not provide `x-amz-server-side-encryption-aws-kms-key-id`, Amazon S3 uses the AWS managed key (`aws/s3`) to protect the data.  
 **Directory buckets** - To encrypt data using SSE-KMS, it's recommended to specify the `x-amz-server-side-encryption` header to `aws:kms`. Then, the `x-amz-server-side-encryption-aws-kms-key-id` header implicitly uses the bucket's default KMS customer managed key ID. If you want to explicitly set the ` x-amz-server-side-encryption-aws-kms-key-id` header, it must match the bucket's default customer managed key (using key ID or ARN, not alias). Your SSE-KMS configuration can only support 1 [customer managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk) per directory bucket's lifetime. The [AWS managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#aws-managed-cmk) (`aws/s3`) isn't supported. Incorrect key specification results in an HTTP `400 Bad Request` error. 

 ** [x-amz-server-side-encryption-bucket-key-enabled](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-BucketKeyEnabled"></a>
Specifies whether Amazon S3 should use an S3 Bucket Key for object encryption with server-side encryption using AWS Key Management Service (AWS KMS) keys (SSE-KMS).  
 **General purpose buckets** - Setting this header to `true` causes Amazon S3 to use an S3 Bucket Key for object encryption with SSE-KMS. Also, specifying this header with a PUT action doesn't affect bucket-level settings for S3 Bucket Key.  
 **Directory buckets** - S3 Bucket Keys are always enabled for `GET` and `PUT` operations in a directory bucket and can’t be disabled. S3 Bucket Keys aren't supported, when you copy SSE-KMS encrypted objects from general purpose buckets to directory buckets, from directory buckets to general purpose buckets, or between directory buckets, through [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html), [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html), [the Copy operation in Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-buckets-objects-Batch-Ops), or [the import jobs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-import-job). In this case, Amazon S3 makes a call to AWS KMS every time a copy request is made for a KMS-encrypted object.

 ** [x-amz-server-side-encryption-context](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-SSEKMSEncryptionContext"></a>
Specifies the AWS KMS Encryption Context as an additional encryption context to use for object encryption. The value of this header is a Base64 encoded string of a UTF-8 encoded JSON, which contains the encryption context as key-value pairs. This value is stored as object metadata and automatically gets passed on to AWS KMS for future `GetObject` operations on this object.  
 **General purpose buckets** - This value must be explicitly added during `CopyObject` operations if you want an additional encryption context for your object. For more information, see [Encryption context](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html#encryption-context) in the *Amazon S3 User Guide*.  
 **Directory buckets** - You can optionally provide an explicit encryption context value. The value must match the default encryption context - the bucket Amazon Resource Name (ARN). An additional encryption context value is not supported. 

 ** [x-amz-server-side-encryption-customer-algorithm](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-SSECustomerAlgorithm"></a>
Specifies the algorithm to use when encrypting the object (for example, `AES256`).  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-SSECustomerKey"></a>
Specifies the customer-provided encryption key for Amazon S3 to use in encrypting data. This value is used to store the object and then it is discarded; Amazon S3 does not store the encryption key. The key must be appropriate for use with the algorithm specified in the `x-amz-server-side-encryption-customer-algorithm` header.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-SSECustomerKeyMD5"></a>
Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error.  
This functionality is not supported for directory buckets.

 ** [x-amz-storage-class](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-StorageClass"></a>
By default, Amazon S3 uses the STANDARD Storage Class to store newly created objects. The STANDARD storage class provides high durability and high availability. Depending on performance needs, you can specify a different Storage Class. For more information, see [Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/dev/storage-class-intro.html) in the *Amazon S3 User Guide*.  
+ Directory buckets only support `EXPRESS_ONEZONE` (the S3 Express One Zone storage class) in Availability Zones and `ONEZONE_IA` (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones.
+ Amazon S3 on Outposts only uses the OUTPOSTS Storage Class.
Valid Values: `STANDARD | REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE | OUTPOSTS | GLACIER_IR | SNOW | EXPRESS_ONEZONE | FSX_OPENZFS | FSX_ONTAP | AWS_BACKUP_WARM | AWS_BACKUP_LOW_COST_WARM` 

 ** [x-amz-tagging](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-Tagging"></a>
The tag-set for the object. The tag-set must be encoded as URL Query parameters. (For example, "Key1=Value1")  
This functionality is not supported for directory buckets.

 ** [x-amz-website-redirect-location](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-WebsiteRedirectLocation"></a>
If the bucket is configured as a website, redirects requests for this object to another object in the same bucket or to an external URL. Amazon S3 stores the value of this header in the object metadata. For information about object metadata, see [Object Key and Metadata](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingMetadata.html) in the *Amazon S3 User Guide*.  
In the following example, the request header sets the redirect to an object (anotherPage.html) in the same bucket:  
 `x-amz-website-redirect-location: /anotherPage.html`   
In the following example, the request header sets the object redirect to another website:  
 `x-amz-website-redirect-location: http://www.example.com/`   
For more information about website hosting in Amazon S3, see [Hosting Websites on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html) and [How to Configure Website Page Redirects](https://docs.aws.amazon.com/AmazonS3/latest/dev/how-to-page-redirect.html) in the *Amazon S3 User Guide*.   
This functionality is not supported for directory buckets.

 ** [x-amz-write-offset-bytes](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-header-WriteOffsetBytes"></a>
 Specifies the offset for appending data to existing objects in bytes. The offset must be equal to the size of the existing object being appended to. If no object exists, setting this header to 0 will create a new object.   
This functionality is only supported for objects in the Amazon S3 Express One Zone storage class in directory buckets.

## Request Body
<a name="API_PutObject_RequestBody"></a>

The request accepts the following binary data.

 ** [Body](#API_PutObject_RequestSyntax) **   <a name="AmazonS3-PutObject-request-Body"></a>

## Response Syntax
<a name="API_PutObject_ResponseSyntax"></a>

```
HTTP/1.1 200
x-amz-expiration: {{Expiration}}
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
x-amz-checksum-type: {{ChecksumType}}
x-amz-server-side-encryption: {{ServerSideEncryption}}
x-amz-version-id: {{VersionId}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-server-side-encryption-aws-kms-key-id: {{SSEKMSKeyId}}
x-amz-server-side-encryption-context: {{SSEKMSEncryptionContext}}
x-amz-server-side-encryption-bucket-key-enabled: {{BucketKeyEnabled}}
x-amz-object-size: {{Size}}
x-amz-request-charged: {{RequestCharged}}
```

## Response Elements
<a name="API_PutObject_ResponseElements"></a>

If the action is successful, the service sends back an HTTP 200 response.

The response returns the following HTTP headers.

 ** [ETag](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ETag"></a>
Entity tag for the uploaded object.  
 **General purpose buckets ** - To ensure that data is not corrupted traversing the network, for objects where the ETag is the MD5 digest of the object, you can calculate the MD5 while putting an object to Amazon S3 and compare the returned ETag to the calculated MD5 value.  
 **Directory buckets ** - The ETag for the object in a directory bucket isn't the MD5 digest of the object.

 ** [x-amz-checksum-crc32](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumCRC32"></a>
The Base64 encoded, 32-bit `CRC32 checksum` of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc32c](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumCRC32C"></a>
The Base64 encoded, 32-bit `CRC32C` checksum of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-crc64nvme](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumCRC64NVME"></a>
The Base64 encoded, 64-bit `CRC64NVME` checksum of the object. This header is present if the object was uploaded with the `CRC64NVME` checksum algorithm, or if it was uploaded without a checksum (and Amazon S3 added the default checksum, `CRC64NVME`, to the uploaded object). For more information about how checksums are calculated with multipart uploads, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-md5](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumMD5"></a>
The Base64 encoded, 128-bit `MD5` digest of the object. This header is present if the object was uploaded with the `MD5` checksum algorithm. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-sha1](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumSHA1"></a>
The Base64 encoded, 160-bit `SHA1` digest of the object. This checksum is only present if the checksum was uploaded with the object. When you use the API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha256](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumSHA256"></a>
The Base64 encoded, 256-bit `SHA256` digest of the object. This checksum is only present if the checksum was uploaded with the object. When you use an API operation on an object that was uploaded using multipart uploads, this value may not be a direct checksum value of the full object. Instead, it's a calculation based on the checksum values of each individual part. For more information about how checksums are calculated with multipart uploads, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html#large-object-checksums) in the *Amazon S3 User Guide*.

 ** [x-amz-checksum-sha512](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumSHA512"></a>
The Base64 encoded, 512-bit `SHA512` digest of the object. This header is present if the object was uploaded with the `SHA512` checksum algorithm. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-type](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumType"></a>
This header specifies the checksum type of the object, which determines how part-level checksums are combined to create an object-level checksum for multipart objects. For `PutObject` uploads, the checksum type is always `FULL_OBJECT`. You can use this header as a data integrity check to verify that the checksum type that is received is the same checksum that was specified. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.  
Valid Values: `COMPOSITE | FULL_OBJECT` 

 ** [x-amz-checksum-xxhash128](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumXXHASH128"></a>
The Base64 encoded, 128-bit `XXHASH128` checksum of the object. This header is present if the object was uploaded with the `XXHASH128` checksum algorithm. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-xxhash3](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumXXHASH3"></a>
The Base64 encoded, 64-bit `XXHASH3` checksum of the object. This header is present if the object was uploaded with the `XXHASH3` checksum algorithm. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-checksum-xxhash64](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ChecksumXXHASH64"></a>
The Base64 encoded, 64-bit `XXHASH64` checksum of the object. This header is present if the object was uploaded with the `XXHASH64` checksum algorithm. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).

 ** [x-amz-expiration](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-Expiration"></a>
If the expiration is configured for the object (see [PutBucketLifecycleConfiguration](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketLifecycleConfiguration.html)) in the *Amazon S3 User Guide*, the response includes this header. It includes the `expiry-date` and `rule-id` key-value pairs that provide information about object expiration. The value of the `rule-id` is URL-encoded.  
Object expiration information is not returned in directory buckets and this header returns the value "`NotImplemented`" in all responses for directory buckets.

 ** [x-amz-object-size](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-Size"></a>
 The size of the object in bytes. This value is only be present if you append to an object.   
This functionality is only supported for objects in the Amazon S3 Express One Zone storage class in directory buckets.

 ** [x-amz-request-charged](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-RequestCharged"></a>
If present, indicates that the requester was successfully charged for the request. For more information, see [Using Requester Pays buckets for storage transfers and usage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html) in the *Amazon Simple Storage Service user guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-server-side-encryption](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-ServerSideEncryption"></a>
The server-side encryption algorithm used when you store this object in Amazon S3 or Amazon FSx.  
When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is `aws:fsx`.
Valid Values: `AES256 | aws:fsx | aws:backup | aws:kms | aws:kms:dsse` 

 ** [x-amz-server-side-encryption-aws-kms-key-id](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-SSEKMSKeyId"></a>
If present, indicates the ID of the KMS key that was used for object encryption.

 ** [x-amz-server-side-encryption-bucket-key-enabled](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-BucketKeyEnabled"></a>
Indicates whether the uploaded object uses an S3 Bucket Key for server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS).

 ** [x-amz-server-side-encryption-context](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-SSEKMSEncryptionContext"></a>
If present, indicates the AWS KMS Encryption Context to use for object encryption. The value of this header is a Base64 encoded string of a UTF-8 encoded JSON, which contains the encryption context as key-value pairs. This value is stored as object metadata and automatically gets passed on to AWS KMS for future `GetObject` operations on this object.

 ** [x-amz-server-side-encryption-customer-algorithm](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-SSECustomerAlgorithm"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to confirm the encryption algorithm that's used.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-SSECustomerKeyMD5"></a>
If server-side encryption with a customer-provided encryption key was requested, the response will include this header to provide the round-trip message integrity verification of the customer-provided encryption key.  
This functionality is not supported for directory buckets.

 ** [x-amz-version-id](#API_PutObject_ResponseSyntax) **   <a name="AmazonS3-PutObject-response-header-VersionId"></a>
Version ID of the object.  
If you enable versioning for a bucket, Amazon S3 automatically generates a unique version ID for the object being stored. Amazon S3 returns this ID in the response. When you enable versioning for a bucket, if Amazon S3 receives multiple write requests for the same object simultaneously, it stores all of the objects. For more information about versioning, see [Adding Objects to Versioning-Enabled Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/AddingObjectstoVersioningEnabledBuckets.html) in the *Amazon S3 User Guide*. For information about returning the versioning state of a bucket, see [GetBucketVersioning](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetBucketVersioning.html).   
This functionality is not supported for directory buckets.

## Errors
<a name="API_PutObject_Errors"></a>

 ** EncryptionTypeMismatch **   
 The existing object was created with a different encryption type. Subsequent write requests must include the appropriate encryption parameters in the request or while creating the session.   
HTTP Status Code: 400

 ** InvalidRequest **   
A parameter or header in your request isn't valid. For details, see the description of this API operation.  
HTTP Status Code: 400

 ** InvalidWriteOffset **   
 The write offset value that you specified does not match the current object size.   
HTTP Status Code: 400

 ** TooManyParts **   
 You have attempted to add more parts than the maximum of 10000 that are allowed for this object. You can use the CopyObject operation to copy this object to another and then add more data to the newly copied object.   
HTTP Status Code: 400

## Examples
<a name="API_PutObject_Examples"></a>

### Example 1 for general purpose buckets: Upload an object
<a name="API_PutObject_Example_1"></a>

The following request stores the `my-image.jpg` file in the `myBucket` bucket.

```
PUT /my-image.jpg HTTP/1.1
Host: myBucket.s3.<Region>.amazonaws.com
Date: Wed, 12 Oct 2009 17:50:00 GMT
Authorization: authorization string
Content-Type: text/plain
Content-Length: 11434
x-amz-meta-author: Janet
Expect: 100-continue
[11434 bytes of object data]
```

### Sample Response for general purpose buckets: Versioning suspended
<a name="API_PutObject_Example_2"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 100 Continue

HTTP/1.1 200 OK
x-amz-id-2: LriYPLdmOdAiIfgSm/F1YsViT1LW94/xUQxMsF7xiEb1a0wiIOIxl+zbwZ163pt7
x-amz-request-id: 0A49CE4060975EAC
Date: Wed, 12 Oct 2009 17:50:00 GMT
ETag: "1b2cf535f27731c974343645a3985328"
Content-Length: 0
Connection: close
Server: AmazonS3
```

### Sample Response for general purpose buckets: Expiration rule created using lifecycle configuration
<a name="API_PutObject_Example_3"></a>

If an expiration rule that was created on the bucket using lifecycle configuration applies to the object, you get a response with an `x-amz-expiration` header, as shown in the following response. For more information, see [Transitioning Objects: General Considerations](https://docs.aws.amazon.com/AmazonS3/latest/dev/object-lifecycle-mgmt.html#lifecycle-transition-general-considerations).

```
HTTP/1.1 100 Continue

HTTP/1.1 200 OK
x-amz-id-2: LriYPLdmOdAiIfgSm/F1YsViT1LW94/xUQxMsF7xiEb1a0wiIOIxl+zbwZ163pt7
x-amz-request-id: 0A49CE4060975EAC
Date: Wed, 12 Oct 2009 17:50:00 GMT
x-amz-expiration: expiry-date="Fri, 23 Dec 2012 00:00:00 GMT", rule-id="1"
ETag: "1b2cf535f27731c974343645a3985328"
Content-Length: 0
Connection: close
Server: AmazonS3
```

### Sample Response for general purpose buckets: Versioning enabled
<a name="API_PutObject_Example_4"></a>

If the bucket has versioning enabled, the response includes the `x-amz-version-id` header.

```
HTTP/1.1 100 Continue

HTTP/1.1 200 OK
x-amz-id-2: LriYPLdmOdAiIfgSm/F1YsViT1LW94/xUQxMsF7xiEb1a0wiIOIxl+zbwZ163pt7
x-amz-request-id: 0A49CE4060975EAC
x-amz-version-id: 43jfkodU8493jnFJD9fjj3HHNVfdsQUIFDNsidf038jfdsjGFDSIRp
Date: Wed, 12 Oct 2009 17:50:00 GMT
ETag: "fbacf535f27731c9771645a39863328"
Content-Length: 0
Connection: close
Server: AmazonS3
```

### Example 2 for general purpose buckets: Specifying the Reduced Redundancy Storage Class
<a name="API_PutObject_Example_5"></a>

The following request stores the image, `my-image.jpg`, in the `myBucket` bucket. The request specifies the `x-amz-storage-class` header to request that the object is stored using the REDUCED\_REDUNDANCY storage class.

```
PUT /my-image.jpg HTTP/1.1
Host: myBucket.s3.<Region>.amazonaws.com
Date: Wed, 12 Oct 2009 17:50:00 GMT
Authorization: authorization string
Content-Type: image/jpeg
Content-Length: 11434
Expect: 100-continue
x-amz-storage-class: REDUCED_REDUNDANCY
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_6"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 100 Continue

HTTP/1.1 200 OK
x-amz-id-2: LriYPLdmOdAiIfgSm/F1YsViT1LW94/xUQxMsF7xiEb1a0wiIOIxl+zbwZ163pt7
x-amz-request-id: 0A49CE4060975EAC
Date: Wed, 12 Oct 2009 17:50:00 GMT
ETag: "1b2cf535f27731c974343645a3985328"
Content-Length: 0
Connection: close
Server: AmazonS3
```

### Example 3 for general purpose buckets: Uploading an object and specifying access permissions explicitly
<a name="API_PutObject_Example_7"></a>

The following request stores the `TestObject.txt` file in the `myBucket` bucket. The request specifies various ACL headers to grant permission to AWS accounts that are specified with a canonical user ID and an email address.

```
PUT TestObject.txt HTTP/1.1
Host: myBucket.s3.<Region>.amazonaws.com
x-amz-date: Fri, 13 Apr 2012 05:40:14 GMT
Authorization: authorization string
x-amz-grant-write-acp: id=8a6925ce4adf588a4532142d3f74dd8c71fa124ExampleCanonicalUserID
x-amz-grant-full-control: emailAddress="ExampleUser@amazon.com"
x-amz-grant-write: emailAddress="ExampleUser1@amazon.com", emailAddress="ExampleUser2@amazon.com"
Content-Length: 300
Expect: 100-continue
Connection: Keep-Alive

...Object data in the body...
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_8"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 200 OK
x-amz-id-2: RUxG2sZJUfS+ezeAS2i0Xj6w/ST6xqF/8pFNHjTjTrECW56SCAUWGg+7QLVoj1GH
x-amz-request-id: 8D017A90827290BA
Date: Fri, 13 Apr 2012 05:40:25 GMT
ETag: "dd038b344cf9553547f8b395a814b274"
Content-Length: 0
Server: AmazonS3
```

### Example 4 for general purpose buckets: Using a canned ACL to set access permissions
<a name="API_PutObject_Example_9"></a>

The following request stores the `TestObject.txt` file in the myBucket bucket. The request uses an `x-amz-acl` header to specify a canned ACL that grants READ permission to the public.

```
PUT TestObject.txt HTTP/1.1
Host: myBucket.s3.<Region>.amazonaws.com
x-amz-date: Fri, 13 Apr 2012 05:54:57 GMT
x-amz-acl: public-read
Authorization: authorization string
Content-Length: 300
Expect: 100-continue
Connection: Keep-Alive

...Object data in the body...
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_10"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 200 OK
x-amz-id-2: Yd6PSJxJFQeTYJ/3dDO7miqJfVMXXW0S2Hijo3WFs4bz6oe2QCVXasxXLZdMfASd
x-amz-request-id: 80DF413BB3D28A25
Date: Fri, 13 Apr 2012 05:54:59 GMT
ETag: "dd038b344cf9553547f8b395a814b274"
Content-Length: 0
Server: AmazonS3
```

### Example 5 for general purpose buckets: Upload an object (Request server-side encryption using a customer-provided encryption key)
<a name="API_PutObject_Example_11"></a>

This example of an upload object requests server-side encryption and provides an encryption key.

**Note**  
If you have server-side encryption with customer-provided keys (SSE-C) blocked for your general purpose bucket, you will get an HTTP 403 Access Denied error when you specify the SSE-C request headers while writing new data to your bucket. For more information, see [Blocking or unblocking SSE-C for a general purpose bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/blocking-unblocking-s3-c-encryption-gpb.html).

```
PUT /example-object HTTP/1.1
Host: example-bucket.s3.<Region>.amazonaws.com   
Accept: */*   
Authorization:authorization string   
Date: Wed, 28 May 2014 19:31:11 +0000   
x-amz-server-side-encryption-customer-key:g0lCfA3Dv40jZz5SQJ1ZukLRFqtI5WorC/8SEEXAMPLE   
x-amz-server-side-encryption-customer-key-MD5:ZjQrne1X/iTcskbY2example   
x-amz-server-side-encryption-customer-algorithm:AES256
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_12"></a>

In the response, Amazon S3 returns the encryption algorithm and MD5 of the encryption key that you specified when uploading the object. The ETag that is returned is not the MD5 of the object.

```
HTTP/1.1 200 OK   
x-amz-id-2: 7qoYGN7uMuFuYS6m7a4lszH6in+hccE+4DXPmDZ7C9KqucjnZC1gI5mshai6fbMG   
x-amz-request-id: 06437EDD40C407C7   
Date: Wed, 28 May 2014 19:31:12 GMT   
x-amz-server-side-encryption-customer-algorithm: AES256   
x-amz-server-side-encryption-customer-key-MD5: ZjQrne1X/iTcskbY2example   
ETag: "ae89237c20e759c5f479ece02c642f59"
```

### Example 6 for general purpose buckets: Upload an object and specify tags
<a name="API_PutObject_Example_13"></a>

This example of an upload object request specifies the optional `x-amz-tagging` header to add tags to the object.

After the object is created, Amazon S3 stores the specified object tags in the tagging subresource that is associated with the object. For more information about tagging, see [Object Tagging and Access Control Policies](https://docs.aws.amazon.com/AmazonS3/latest/dev/object-tagging.html#tagging-and-policies) in the *Amazon S3 User Guide*.

```
PUT /example-object HTTP/1.1
Host: example-bucket.s3.<Region>.amazonaws.com   
Accept: */*   
Authorization:authorization string   
Date: Thu, 22 Sep 2016 21:58:13 GMT   
x-amz-tagging: tag1=value1&tag2=value2

[... bytes of object data]
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_14"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 200 OK   
x-amz-id-2: 7qoYGN7uMuFuYS6m7a4lszH6in+hccE+4DXPmDZ7C9KqucjnZC1gI5mshai6fbMG   
x-amz-request-id: 06437EDD40C407C7   
Date: Thu, 22 Sep 2016 21:58:17 GMT
```

### Example 7 for general purpose buckets: Upload an object and specify the checksum algorithm
<a name="API_PutObject_Example_15"></a>

This example of an upload object request specifies the additional checksum algorithm to use to verify the content of the object. For more information about using additional checksums, see [ Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon S3 User Guide*.

```
PUT /example-object HTTP/1.1
Host: example-bucket.s3.<Region>.amazonaws.com
x-amz-date: Mon, 22 Mar 2021 23:00:00 GMT
Authorization: authorization string
Content-Length: 268435456
x-amz-checksum-sha256: 0ea4be78f6c3948588172edc6d8789ffe3cec461f385e0ac447e581731c429b5
[268435456 bytes of object data in the body]
```

### Sample Response for general purpose buckets
<a name="API_PutObject_Example_16"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 200 OK
x-amz-id-2: 7qoYGN7uMuFuYS6m7a4lszH6in+hccE+4DXPmDZ7C9KqucjnZC1gI5mshai6fbMG
x-amz-request-id: 49CFA2051300FBE9
Date: Mon, 22 Mar 2021 23:00:12 GMT
```

### Example 8 for directory buckets: Upload an object and append to it
<a name="API_PutObject_Example_17"></a>

The following request creates the `my-application.log` file in the `mybucket` bucket, and appends to it afterwards.

```
PUT /my-application.log HTTP/1.1
Host: mybucket--usw2-az1--x-s3
Date: Fri, 22 Nov 2024 17:50:00 GMT
Authorization: authorization string
Content-Type: text/plain
Content-Length: 1048576
[1048576 bytes of object data]

PUT /my-application.log HTTP/1.1
Host: mybucket--usw2-az1--x-s3
Date: Fri, 22 Nov 2024 17:50:00 GMT
Authorization: authorization string
Content-Type: text/plain
Content-Length: 524288
x-amz-write-offset-bytes: 1048576
[524288 bytes of object data]
```

### Sample Response for directory buckets
<a name="API_PutObject_Example_18"></a>

This example illustrates one usage of PutObject.

```
HTTP/1.1 200 OK
x-amz-request-id: 06437EDD40C407C7
x-amz-id-2: 7qoYGN7uMuFuYS6m7a4lszH6in+hccE+4DXPmDZ7C9KqucjnZC1gI5mshai6fbMG   
etag: "ae89237c20e759c5f479ece02c642f59"
x-amz-object-size: 1572864
```

## Constraints (AI generated)
<a name="PutObject-constraints"></a>

This content was generated using AI technology that has in-depth knowledge of AWS API operations. [Provide feedback on this content.](https://docs-feedback.aws.amazon.com/feedback.jsp?hidden_service_name=S3&topic_url=https://[…]mazon.com/en_us/AmazonS3/latest/API/API_PutObject.html) 

For Encryption parameters:
+ You must not pass parameters that don't apply to the type of encryption that you're setting. For example, you cannot pass both `SSECustomerKey`, which is used for server-side encryption with customer-provided keys (SSE-C), and `SSEKMSKeyId`, which is used for server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS), in the same request.
+ When using server-side encryption with customer-provided keys (SSE-C), you must pass all three parameters: `SSECustomerAlgorithm`, `SSECustomerKey`, and `SSECustomerKeyMD5`. In addition, the value of `SSECustomerAlgorithm` must be `AES256`.
+ When using server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS), you must set the value of `ServerSideEncryption` to `aws:kms`. You can also use `SSEKMSKeyId` to specify the ARN for a specific customer managed KMS encryption key. Additionally, you cannot pass `SSECustomerAlgorithm` when using SSE-KMS.

For Object Lock parameters:
+ Object Lock parameters must be paired. If you specify `ObjectLockMode`, you must also specify `ObjectLockRetainUntilDate`, and vice versa. Either specify both parameters or neither one.

For Checksum parameters:
+ When you specify a particular `ChecksumAlgorithm` value, you can only pass the checksum parameter that corresponds to that algorithm. For example, if you specify the value `CRC32` for `ChecksumAlgorithm`, you must only pass `ChecksumCRC32` for the CRC-32 algorithm. In this case, you cannot pass any of the following parameters, which are specific to the CRC-32C `(CRC32C)`, SHA-1 `(SHA1)`, and SHA-256 `(SHA256)` checksum algorithms respectively: `ChecksumCRC32C`, `ChecksumSHA1`, or `ChecksumSHA256`.

## See Also
<a name="API_PutObject_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS Command Line Interface V2](https://docs.aws.amazon.com/goto/cli2/s3-2006-03-01/PutObject) 
+  [AWS SDK for .NET V4](https://docs.aws.amazon.com/goto/DotNetSDKV4/s3-2006-03-01/PutObject) 
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/PutObject) 
+  [AWS SDK for Go v2](https://docs.aws.amazon.com/goto/SdkForGoV2/s3-2006-03-01/PutObject) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/PutObject) 
+  [AWS SDK for JavaScript V3](https://docs.aws.amazon.com/goto/SdkForJavaScriptV3/s3-2006-03-01/PutObject) 
+  [AWS SDK for Kotlin](https://docs.aws.amazon.com/goto/SdkForKotlin/s3-2006-03-01/PutObject) 
+  [AWS SDK for PHP V3](https://docs.aws.amazon.com/goto/SdkForPHPV3/s3-2006-03-01/PutObject) 
+  [AWS SDK for Python (Boto3)](https://docs.aws.amazon.com/goto/boto3/s3-2006-03-01/PutObject) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/PutObject) 