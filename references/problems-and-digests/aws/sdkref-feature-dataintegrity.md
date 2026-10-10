

# Data Integrity Protections for Amazon S3
<a name="feature-dataintegrity"></a>

**Note**  
For help in understanding the layout of settings pages, or in interpreting the **Support by AWS SDKs and tools** table that follows, see [Understanding the settings pages of this guide](settings-reference.md#settingsPages).

For some time, AWS SDKs have supported data integrity checks when uploading data to or downloading data from Amazon Simple Storage Service. Previously, these checks were opt-in. Now, we've enabled these checks by default, using CRC-based algorithms such as CRC32 or CRC64NVME. Although each SDK or tool has a default algorithm, you can choose a different algorithm. You can also continue to still manually supply a pre-calculated checksum for uploads if you want. Consistent behavior across uploads, multipart uploads, downloads, and encryption modes simplifies client-side integrity checks. 

 The latest versions of our AWS SDKs and AWS CLI automatically calculate a [cyclic redundancy check (CRC)-based checksum](https://en.wikipedia.org/wiki/Cyclic_redundancy_check) for each upload and sends it to Amazon S3. Amazon S3 independently calculates a checksum on the server side and validates it against the provided value before durably storing the object and its checksum in the object's metadata. By storing the checksum in the metadata alongside the object, when the object is downloaded, the same checksum can be automatically returned and used to validate downloads as well. You can also verify the checksum stored in the object's metadata at any time. 

 To learn more about checksum operations, multipart uploads, or the list of supported checksum algorithms, see [Checking object integrity in Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the *Amazon Simple Storage Service User Guide*. 

 **Multipart uploads:**

Amazon S3 also provides developers with consistent full object checksums across single part and multipart uploads. 

When uploading files in multiple parts, the SDKs calculate checksums for each part. Amazon S3 uses these checksums to verify the integrity of each part through the `UploadPart` API. Additionally, Amazon S3 validates the entire file's size and checksum when you call the `CompleteMultipartUpload` API. 

If your SDK has an Amazon S3 Transfer Manager to assist with multipart uploads, the checksums are validated for the parts using the SDK-specific default algorithm found in the [Support by AWS SDKs and tools](#dataintegrity-sdk-compat) table. You can opt-in to a full object checksum by setting setting `checksum_type` to `FULL_OBJECT` or by choosing to use the CRC64NVME algorithm.

** If you are using an older version of SDK or AWS CLI:** 

If your application uses a version prior to December 2024 of the SDK or tool, Amazon S3 still computes a CRC64NVME checksum on new objects and stores it in the object metadata for future reference. You can later compare the stored CRC with a CRC computed on your side and verify the network transmission was correct. Also, you can still manually extend the integrity protection by providing your own precomputed checksums with your [`PutObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html) or [`UploadPart`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html) requests, which is the standard technique for addressing this in older versions. 



Configure this functionality by using the following:

**`request_checksum_calculation` - shared AWS `config` file setting`AWS_REQUEST_CHECKSUM_CALCULATION` - environment variable`aws.requestChecksumCalculation` - JVM system property: Java/Kotlin only**  
By default, users are opted-in to calculating a request checksum when sending a request. The user can choose any of the [available checksum algorithms](https://docs.aws.amazon.com/AmazonS3/latest/API/API_Checksum.html) as a part of building the request. Otherwise, an SDK-specific default algorithm is used. See the [Support by AWS SDKs and tools](#dataintegrity-sdk-compat) table for the default algorithm for each SDK or tool.  
**Default value:** `WHEN_SUPPORTED`  
**Valid values:**  
+ **`WHEN_SUPPORTED`** – Checksum validation is performed on all request payloads when supported by the API operation, such as data transfers to Amazon S3.
+ **`WHEN_REQUIRED`** – Checksum validation is performed only when required by the API operation.

**`response_checksum_validation` - shared AWS `config` file setting`AWS_RESPONSE_CHECKSUM_VALIDATION` - environment variable`aws.responseChecksumValidation` - JVM system property: Java/Kotlin only**  
By default, users are opted-in to a response checksum validation when sending a request. A checksum is calculated for the response payload and compared against the checksum response header. If checksum validation fails, an error is raised to the user when the payload is read.  
 The checksum response header also indicates the algorithm for the checksum. The Amazon S3 client attempts to validate response checksums for all Amazon S3 API operations that support checksums. However, if the SDK has not implemented the specified checksum algorithm then this validation is skipped.   
**Default value:** `WHEN_SUPPORTED`  
**Valid values:**  
+ **`WHEN_SUPPORTED`** – Checksum validation is performed on all response payloads when supported by the API operation, such as data transfers to Amazon S3.
+ **`WHEN_REQUIRED`** – Checksum validation is performed only when supported by the API operation and the caller has explicitly enabled checksum for the operation. For example, when the Amazon S3 `GetObject` API is called and the `ChecksumMode` parameter is set to enabled.

## Support by AWS SDKs and tools
<a name="dataintegrity-sdk-compat"></a>

The following SDKs support the features and settings described in this topic. Any partial exceptions are noted. Any JVM system property settings are supported by the AWS SDK for Java and the AWS SDK for Kotlin only.

**Note**  
In the following table, 'CRT' refers to the [AWS Common Runtime (CRT) libraries](common-runtime.md) and might require adding an additional dependency to your project.


| SDK | Supported | Default checksum algorithm | Supported checksum algorithms | Notes or more information | 
| --- | --- | --- | --- | --- | 
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/) | Yes | CRC64NVME | CRC64NVME, CRC32, CRC32C, SHA1, SHA256, xxHash3, xxHash64, xxHash128, SHA512 | For AWS CLI v1, the default algorithm and the supported algorithms will be identical to Python (Boto3). | 
| [SDK for C\+\+](https://docs.aws.amazon.com/sdk-for-cpp/latest/developer-guide/) | Yes | CRC64NVME | CRC64NVME, CRC32, CRC32C, SHA1, SHA256, xxHash3, xxHash64, xxHash128, SHA512  |  | 
| [SDK for Go V2 (1.x)](https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/) | Yes | CRC32 | CRC64NVME, CRC32, CRC32C, SHA1, SHA256 |  | 
| [SDK for Go 1.x (V1)](https://docs.aws.amazon.com/sdk-for-go/latest/developer-guide/) | No |  |  |  | 
| [SDK for Java 2.x](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256<br />**Via CRT only:** CRC64NVME, xxHash3, xxHash64, xxHash128, SHA512 |  | 
| [SDK for Java 1.x](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/) | No |  |  |  | 
| [SDK for JavaScript 3.x](https://docs.aws.amazon.com/sdk-for-javascript/latest/developer-guide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256 |  | 
| [SDK for JavaScript 2.x](https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/) | No |  |  |  | 
| [SDK for Kotlin](https://docs.aws.amazon.com/sdk-for-kotlin/latest/developer-guide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256 |  | 
| [SDK for .NET 4.x](https://docs.aws.amazon.com/sdk-for-net/latest/developer-guide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256, SHA512 |  | 
| [SDK for .NET 3.x](https://docs.aws.amazon.com/sdk-for-net/v3/developer-guide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256, SHA512 |  | 
| [SDK for PHP 3.x](https://docs.aws.amazon.com/sdk-for-php/latest/developer-guide/) | Yes | CRC32 | CRC32, SHA1, SHA256<br />**Via CRT only:** CRC32C | awscrt extension is required in order to use CRC32C. | 
| [SDK for Python (Boto3)](https://docs.aws.amazon.com/boto3/latest/) | Yes | CRC32 | CRC32, SHA1, SHA256<br />**Via CRT only:** CRC32C, CRC64NVME, xxHash3, xxHash64, xxHash128, SHA512 |  | 
| [SDK for Ruby 3.x](https://docs.aws.amazon.com/sdk-for-ruby/latest/developer-guide/) | Yes | CRC32 | CRC32, SHA1, SHA256<br />**Via CRT only:** CRC64NVME, CRC32C |  | 
| [SDK for Rust](https://docs.aws.amazon.com/sdk-for-rust/latest/dg/) | Yes | CRC32 | CRC64NVME, CRC32, CRC32C, SHA1, SHA256 |  | 
| [SDK for Swift](https://docs.aws.amazon.com/sdk-for-swift/latest/developer-guide/) | Yes | CRC32 | CRC64NVME, CRC32, CRC32C, SHA1, SHA256 | CRT dependency required for all algorithms. | 
| [Tools for PowerShell V5](https://docs.aws.amazon.com/powershell/latest/userguide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256, xxHash3, SHA512 |  | 
| [Tools for PowerShell V4](https://docs.aws.amazon.com/powershell/v4/userguide/) | Yes | CRC32 | CRC32, CRC32C, SHA1, SHA256, SHA512 |  | 