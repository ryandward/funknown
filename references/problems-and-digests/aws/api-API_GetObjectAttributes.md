

# GetObjectAttributes
<a name="API_GetObjectAttributes"></a>

Retrieves all of the metadata from an object without returning the object itself. This operation is useful if you're interested only in an object's metadata. 

 `GetObjectAttributes` combines the functionality of `HeadObject` and `ListParts`. All of the data returned with both of those individual calls can be returned with a single call to `GetObjectAttributes`.

**Note**  
 **Directory buckets** - For directory buckets, you must make requests for this API operation to the Zonal endpoint. These endpoints support virtual-hosted-style requests in the format `https://amzn-s3-demo-bucket.s3express-zone-id.region-code.amazonaws.com/key-name `. Path-style requests are not supported. For more information about endpoints in Availability Zones, see [Regional and Zonal endpoints for directory buckets in Availability Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/endpoint-directory-buckets-AZ.html) in the *Amazon S3 User Guide*. For more information about endpoints in Local Zones, see [Concepts for directory buckets in Local Zones](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-lzs-for-directory-buckets.html) in the *Amazon S3 User Guide*.

Permissions  
+  **General purpose bucket permissions** - To use `GetObjectAttributes`, you must have READ access to the object.

  The other permissions that you need to use this operation depend on whether the bucket is versioned and if a version ID is passed in the `GetObjectAttributes` request. 
  + If you pass a version ID in your request, you need both the `s3:GetObjectVersion` and `s3:GetObjectVersionAttributes` permissions.
  + If you do not pass a version ID in your request, you need the `s3:GetObject` and `s3:GetObjectAttributes` permissions. 

  For more information, see [Specifying Permissions in a Policy](https://docs.aws.amazon.com/AmazonS3/latest/dev/using-with-s3-actions.html) in the *Amazon S3 User Guide*.

  If the object that you request does not exist, the error Amazon S3 returns depends on whether you also have the `s3:ListBucket` permission.
  + If you have the `s3:ListBucket` permission on the bucket, Amazon S3 returns an HTTP status code `404 Not Found` ("no such key") error.
  + If you don't have the `s3:ListBucket` permission, Amazon S3 returns an HTTP status code `403 Forbidden` ("access denied") error.
+  **Directory bucket permissions** - To grant access to this API operation on a directory bucket, we recommend that you use the [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html) API operation for session-based authorization. Specifically, you grant the `s3express:CreateSession` permission to the directory bucket in a bucket policy or an IAM identity-based policy. Then, you make the `CreateSession` API call on the bucket to obtain a session token. With the session token in your request header, you can make API requests to this operation. After the session token expires, you make another `CreateSession` API call to generate a new session token for use. AWS CLI or SDKs create session and refresh the session token automatically to avoid service interruptions when a session expires. For more information about authorization, see [`CreateSession`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html).

  If the object is encrypted with SSE-KMS, you must also have the `kms:GenerateDataKey` and `kms:Decrypt` permissions in IAM identity-based policies and AWS KMS key policies for the AWS KMS key.

Encryption  
Encryption request headers, like `x-amz-server-side-encryption`, should not be sent for `HEAD` requests if your object uses server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS), dual-layer server-side encryption with AWS KMS keys (DSSE-KMS), or server-side encryption with Amazon S3 managed encryption keys (SSE-S3). The `x-amz-server-side-encryption` header is used when you `PUT` an object to S3 and want to specify the encryption method. If you include this header in a `GET` request for an object that uses these types of keys, you’ll get an HTTP `400 Bad Request` error. It's because the encryption method can't be changed when you retrieve the object.
If you encrypted an object when you stored the object in Amazon S3 by using server-side encryption with customer-provided encryption keys (SSE-C), then when you retrieve the metadata from the object, you must use the following headers. These headers provide the server with the encryption key required to retrieve the object's metadata. The headers are:   
+  `x-amz-server-side-encryption-customer-algorithm` 
+  `x-amz-server-side-encryption-customer-key` 
+  `x-amz-server-side-encryption-customer-key-MD5` 
For more information about SSE-C, see [Server-Side Encryption (Using Customer-Provided Encryption Keys)](https://docs.aws.amazon.com/AmazonS3/latest/dev/ServerSideEncryptionCustomerKeys.html) in the *Amazon S3 User Guide*.  
 **Directory bucket permissions** - For directory buckets, there are only two supported options for server-side encryption: server-side encryption with Amazon S3 managed keys (SSE-S3) (`AES256`) and server-side encryption with AWS KMS keys (SSE-KMS) (`aws:kms`). We recommend that the bucket's default encryption uses the desired encryption configuration and you don't override the bucket default encryption in your `CreateSession` requests or `PUT` object requests. Then, new objects are automatically encrypted with the desired encryption settings. For more information, see [Protecting data with server-side encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-serv-side-encryption.html) in the *Amazon S3 User Guide*. For more information about the encryption overriding behaviors in directory buckets, see [Specifying server-side encryption with AWS KMS for new object uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-specifying-kms-encryption.html).

Versioning  
 **Directory buckets** - S3 Versioning isn't enabled and supported for directory buckets. For this API operation, only the `null` value of the version ID is supported by directory buckets. You can only specify `null` to the `versionId` query parameter in the request.

Conditional request headers  
Consider the following when using request headers:  
+ If both of the `If-Match` and `If-Unmodified-Since` headers are present in the request as follows, then Amazon S3 returns the HTTP status code `200 OK` and the data requested:
  +  `If-Match` condition evaluates to `true`.
  +  `If-Unmodified-Since` condition evaluates to `false`.

  For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).
+ If both of the `If-None-Match` and `If-Modified-Since` headers are present in the request as follows, then Amazon S3 returns the HTTP status code `304 Not Modified`:
  +  `If-None-Match` condition evaluates to `false`.
  +  `If-Modified-Since` condition evaluates to `true`.

  For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).

HTTP Host header syntax  
 **Directory buckets ** - The HTTP Host header syntax is ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`.

The following actions are related to `GetObjectAttributes`:
+  [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html) 
+  [GetObjectAcl](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectAcl.html) 
+  [GetObjectLegalHold](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectLegalHold.html) 
+  [GetObjectLockConfiguration](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectLockConfiguration.html) 
+  [GetObjectRetention](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectRetention.html) 
+  [GetObjectTagging](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectTagging.html) 
+  [HeadObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html) 
+  [ListParts](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListParts.html) 

**Important**  
You must URL encode any signed header values that contain spaces. For example, if your header value is `my file.txt`, containing two spaces after `my`, you must URL encode this value to `my%20%20file.txt`.

## Request Syntax
<a name="API_GetObjectAttributes_RequestSyntax"></a>

```
GET /{Key+}?attributes&versionId={{VersionId}} HTTP/1.1
Host: {{Bucket}}.s3.amazonaws.com
x-amz-max-parts: {{MaxParts}}
x-amz-part-number-marker: {{PartNumberMarker}}
x-amz-server-side-encryption-customer-algorithm: {{SSECustomerAlgorithm}}
x-amz-server-side-encryption-customer-key: {{SSECustomerKey}}
x-amz-server-side-encryption-customer-key-MD5: {{SSECustomerKeyMD5}}
x-amz-request-payer: {{RequestPayer}}
x-amz-expected-bucket-owner: {{ExpectedBucketOwner}}
x-amz-object-attributes: {{ObjectAttributes}}
```

## URI Request Parameters
<a name="API_GetObjectAttributes_RequestParameters"></a>

The request uses the following URI parameters.

 ** [Bucket](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-Bucket"></a>
The name of the bucket that contains the object.  
 **Directory buckets** - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format ` Bucket-name.s3express-zone-id.region-code.amazonaws.com`. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format ` bucket-base-name--zone-id--x-s3` (for example, ` amzn-s3-demo-bucket--usw2-az1--x-s3`). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the *Amazon S3 User Guide*.  
 **Access points** - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form *AccessPointName*-*AccountId*.s3-accesspoint.*Region*.amazonaws.com. When using this action with an access point through the AWS SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the *Amazon S3 User Guide*.  
Object Lambda access points are not supported by directory buckets.
 **S3 on Outposts** - When you use this action with S3 on Outposts, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form ` AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com`. When you use this action with S3 on Outposts, the destination bucket must be the Outposts access point ARN or the access point alias. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the *Amazon S3 User Guide*.  
Required: Yes

 ** [Key](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-uri-uri-Key"></a>
The object key.  
Length Constraints: Minimum length of 1.  
Required: Yes

 ** [versionId](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-uri-querystring-VersionId"></a>
The version ID used to reference a specific version of the object.  
S3 Versioning isn't enabled and supported for directory buckets. For this API operation, only the `null` value of the version ID is supported by directory buckets. You can only specify `null` to the `versionId` query parameter in the request.

 ** [x-amz-expected-bucket-owner](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-ExpectedBucketOwner"></a>
The account ID of the expected bucket owner. If the account ID that you provide does not match the actual owner of the bucket, the request fails with the HTTP status code `403 Forbidden` (access denied).

 ** [x-amz-max-parts](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-MaxParts"></a>
Sets the maximum number of parts to return. For more information, see [Uploading and copying objects using multipart upload in Amazon S3 ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html) in the *Amazon Simple Storage Service user guide*.

 ** [x-amz-object-attributes](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-ObjectAttributes"></a>
Specifies the fields at the root level that you want returned in the response. Fields that you do not specify are not returned.  
Valid Values: `ETag | Checksum | ObjectParts | StorageClass | ObjectSize`   
Required: Yes

 ** [x-amz-part-number-marker](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-PartNumberMarker"></a>
Specifies the part after which listing should begin. Only parts with higher part numbers will be listed. For more information, see [Uploading and copying objects using multipart upload in Amazon S3 ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html) in the *Amazon Simple Storage Service user guide*.

 ** [x-amz-request-payer](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-RequestPayer"></a>
Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for the corresponding charges. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the *Amazon S3 User Guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-server-side-encryption-customer-algorithm](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-SSECustomerAlgorithm"></a>
Specifies the algorithm to use when encrypting the object (for example, AES256).  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-SSECustomerKey"></a>
Specifies the customer-provided encryption key for Amazon S3 to use in encrypting data. This value is used to store the object and then it is discarded; Amazon S3 does not store the encryption key. The key must be appropriate for use with the algorithm specified in the `x-amz-server-side-encryption-customer-algorithm` header.  
This functionality is not supported for directory buckets.

 ** [x-amz-server-side-encryption-customer-key-MD5](#API_GetObjectAttributes_RequestSyntax) **   <a name="AmazonS3-GetObjectAttributes-request-header-SSECustomerKeyMD5"></a>
Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error.  
This functionality is not supported for directory buckets.

## Request Body
<a name="API_GetObjectAttributes_RequestBody"></a>

The request does not have a request body.

## Response Syntax
<a name="API_GetObjectAttributes_ResponseSyntax"></a>

```
HTTP/1.1 200
x-amz-delete-marker: {{DeleteMarker}}
Last-Modified: {{LastModified}}
x-amz-version-id: {{VersionId}}
x-amz-request-charged: {{RequestCharged}}
<?xml version="1.0" encoding="UTF-8"?>
<GetObjectAttributesResponse>
   <ETag>string</ETag>
   <Checksum>
      <ChecksumCRC32>string</ChecksumCRC32>
      <ChecksumCRC32C>string</ChecksumCRC32C>
      <ChecksumCRC64NVME>string</ChecksumCRC64NVME>
      <ChecksumMD5>string</ChecksumMD5>
      <ChecksumSHA1>string</ChecksumSHA1>
      <ChecksumSHA256>string</ChecksumSHA256>
      <ChecksumSHA512>string</ChecksumSHA512>
      <ChecksumType>string</ChecksumType>
      <ChecksumXXHASH128>string</ChecksumXXHASH128>
      <ChecksumXXHASH3>string</ChecksumXXHASH3>
      <ChecksumXXHASH64>string</ChecksumXXHASH64>
   </Checksum>
   <ObjectParts>
      <IsTruncated>boolean</IsTruncated>
      <MaxParts>integer</MaxParts>
      <NextPartNumberMarker>integer</NextPartNumberMarker>
      <PartNumberMarker>integer</PartNumberMarker>
      <Part>
         <ChecksumCRC32>string</ChecksumCRC32>
         <ChecksumCRC32C>string</ChecksumCRC32C>
         <ChecksumCRC64NVME>string</ChecksumCRC64NVME>
         <ChecksumMD5>string</ChecksumMD5>
         <ChecksumSHA1>string</ChecksumSHA1>
         <ChecksumSHA256>string</ChecksumSHA256>
         <ChecksumSHA512>string</ChecksumSHA512>
         <ChecksumXXHASH128>string</ChecksumXXHASH128>
         <ChecksumXXHASH3>string</ChecksumXXHASH3>
         <ChecksumXXHASH64>string</ChecksumXXHASH64>
         <PartNumber>integer</PartNumber>
         <Size>long</Size>
      </Part>
      ...
      <PartsCount>integer</PartsCount>
   </ObjectParts>
   <StorageClass>string</StorageClass>
   <ObjectSize>long</ObjectSize>
</GetObjectAttributesResponse>
```

## Response Elements
<a name="API_GetObjectAttributes_ResponseElements"></a>

If the action is successful, the service sends back an HTTP 200 response.

The response returns the following HTTP headers.

 ** [Last-Modified](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-header-LastModified"></a>
Date and time when the object was last modified.

 ** [x-amz-delete-marker](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-header-DeleteMarker"></a>
Specifies whether the object retrieved was (`true`) or was not (`false`) a delete marker. If `false`, this response header does not appear in the response. To learn more about delete markers, see [Working with delete markers](https://docs.aws.amazon.com/AmazonS3/latest/userguide/DeleteMarker.html).  
This functionality is not supported for directory buckets.

 ** [x-amz-request-charged](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-header-RequestCharged"></a>
If present, indicates that the requester was successfully charged for the request. For more information, see [Using Requester Pays buckets for storage transfers and usage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html) in the *Amazon Simple Storage Service user guide*.  
This functionality is not supported for directory buckets.
Valid Values: `requester` 

 ** [x-amz-version-id](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-header-VersionId"></a>
The version ID of the object.  
This functionality is not supported for directory buckets.

The following data is returned in XML format by the service.

 ** [GetObjectAttributesResponse](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-GetObjectAttributesOutput"></a>
Root level tag for the GetObjectAttributesResponse parameters.  
Required: Yes

 ** [Checksum](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-Checksum"></a>
The checksum or digest of the object.  
Type: [Checksum](API_Checksum.md) data type

 ** [ETag](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-ETag"></a>
An ETag is an opaque identifier assigned by a web server to a specific version of a resource found at a URL.  
Type: String

 ** [ObjectParts](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-ObjectParts"></a>
A collection of parts associated with a multipart upload.  
Type: [GetObjectAttributesParts](API_GetObjectAttributesParts.md) data type

 ** [ObjectSize](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-ObjectSize"></a>
The size of the object in bytes.  
Type: Long

 ** [StorageClass](#API_GetObjectAttributes_ResponseSyntax) **   <a name="AmazonS3-GetObjectAttributes-response-StorageClass"></a>
Provides the storage class information of the object. Amazon S3 returns this header for all objects except for S3 Standard storage class objects.  
For more information, see [Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/dev/storage-class-intro.html).  
 **Directory buckets** - Directory buckets only support `EXPRESS_ONEZONE` (the S3 Express One Zone storage class) in Availability Zones and `ONEZONE_IA` (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones.
Type: String  
Valid Values: `STANDARD | REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE | OUTPOSTS | GLACIER_IR | SNOW | EXPRESS_ONEZONE | FSX_OPENZFS | FSX_ONTAP | AWS_BACKUP_WARM | AWS_BACKUP_LOW_COST_WARM` 

## Errors
<a name="API_GetObjectAttributes_Errors"></a>

 ** NoSuchKey **   
The specified key does not exist.  
HTTP Status Code: 404

## See Also
<a name="API_GetObjectAttributes_SeeAlso"></a>

For more information about using this API in one of the language-specific AWS SDKs, see the following:
+  [AWS Command Line Interface V2](https://docs.aws.amazon.com/goto/cli2/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for .NET V4](https://docs.aws.amazon.com/goto/DotNetSDKV4/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for C\+\+](https://docs.aws.amazon.com/goto/SdkForCpp/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for Go v2](https://docs.aws.amazon.com/goto/SdkForGoV2/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for Java V2](https://docs.aws.amazon.com/goto/SdkForJavaV2/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for JavaScript V3](https://docs.aws.amazon.com/goto/SdkForJavaScriptV3/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for Kotlin](https://docs.aws.amazon.com/goto/SdkForKotlin/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for PHP V3](https://docs.aws.amazon.com/goto/SdkForPHPV3/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for Python (Boto3)](https://docs.aws.amazon.com/goto/boto3/s3-2006-03-01/GetObjectAttributes) 
+  [AWS SDK for Ruby V3](https://docs.aws.amazon.com/goto/SdkForRubyV3/s3-2006-03-01/GetObjectAttributes) 