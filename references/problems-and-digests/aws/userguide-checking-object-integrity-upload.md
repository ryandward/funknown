

# Checking object integrity for data uploads in Amazon S3
<a name="checking-object-integrity-upload"></a>

Amazon S3 uses checksum values to verify data integrity during upload and download operations. When you upload data, AWS SDK and the AWS Management Console use your chosen checksum algorithm to compute a checksum value before data transmission. S3 then independently calculates a checksum of your data and validates it against the provided checksum value. Objects are accepted only after confirming data integrity was maintained during transit. S3 stores both the checksum value as object metadata and the object itself.

To verify object integrity, you can request the checksum value during downloads. This validation works consistently across encryption modes, object sizes, storage classes, and both single part and multipart uploads. To change the checksum algorithm for an upload, you can copy an individual object or use batch copy for multiple objects.

For single part uploads, you can provide checksum values as headers. You can either provide a pre-calculated value or let the AWS SDK calculate one during upload. If the checksum value calculated by S3 matches your provided value, the request is accepted. If the values don't match, the request is rejected.

For multipart uploads, AWS SDKs can automatically create trailing checksums for chunked uploads. When you use a trailing checksum, Amazon S3 generates checksum values for every part using your specified algorithm and appends the checksum value to the end of the chunked upload request. S3 performs the verification and upload in a single pass, improving efficiency. For more information, see see [Using trailing checksums](#trailing-checksums).

## Using supported checksum algorithms
<a name="using-additional-checksums"></a>

With Amazon S3, you can choose a checksum algorithm to calculate the checksum values during uploads. The specified checksum algorithm is then stored with your object and can be used to validate data integrity during downloads. You can choose one of the following Secure Hash Algorithms (SHA) or Cyclic Redundancy Check (CRC) checksum algorithms to calculate the checksum value:
+ CRC-64/NVME (`CRC64NVME`)
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
The `content-MD5` header is only available using the S3 ETag for objects uploaded in a single part upload (`PUT` operation) that uses the SSE-S3 encryption.

Additionally, you can provide a checksum with each request using the Content-MD5 header.

When you [upload an object](https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html), you specify the algorithm that you want to use: 
+ **When you use the AWS Management Console**, choose the checksum algorithm that you want to use. You can optionally specify the checksum value of the object. When Amazon S3 receives the object, it calculates the checksum by using the algorithm that you specified. If the two checksum values don't match, Amazon S3 generates an error.
+ **When you use an SDK**, be aware of the following:
  + Set the `ChecksumAlgorithm` parameter to the algorithm that you want Amazon S3 to use. If you already have a precalculated checksum, you pass the checksum value to the AWS SDK, and the SDK includes the value in the request. If you don’t pass a checksum value or don’t specify a checksum algorithm, the SDK automatically calculates a checksum value for you and includes it with the request to provide integrity protections. If the individual checksum value doesn't match the set value of the checksum algorithm, Amazon S3 fails the request with a `BadDigest` error.
  + If you’re using an upgraded AWS SDK, the SDK chooses a checksum algorithm for you. However, you can override this checksum algorithm.
  + If you don’t specify a checksum algorithm and the SDK also doesn’t calculate a checksum for you, then S3 automatically chooses the CRC-64/NVME (`CRC64NVME`) checksum algorithm.
+ **When you use the REST API**, don't use the `x-amz-sdk-checksum-algorithm` parameter. Instead, use one of the algorithm-specific headers (for example, `x-amz-checksum-crc32`).

To apply any of these checksum values to objects that are already uploaded to Amazon S3, you can copy the object and specify whether you want to use the existing checksum algorithm or a new one. If you don’t specify an algorithm, S3 uses the existing algorithm. If the source object doesn’t have a specified checksum algorithm or checksum value, Amazon S3 uses the CRC-64/NVME algorithm to calculate the checksum value for the destination object. You can also specify a checksum algorithm when copying objects using [S3 Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html).

**Important**  
If you use a multipart upload with **Checksums** for composite (or part-level) checksums, the multipart upload part numbers must be consecutive and begin with 1. If you try to complete a multipart upload request with nonconsecutive part numbers, Amazon S3 generates an `HTTP 500 Internal Server` error.

## Full object and composite checksum types
<a name="ChecksumTypes-Uploads"></a>

In Amazon S3, there are two types of supported checksums:
+ **Full object checksums:** A full object checksum is calculated based on all of the content of a multipart upload, covering all data from the first byte of the first part to the last byte of the last part. Be aware that if you're using the AWS Management Console to upload objects that are smaller than 16 MB, only the full object checksum type is supported. 
**Note**  
Objects that you upload using [`PutObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html#API_PutObject) use the full object checksum type. You do not need to specify a checksum type.
+ **Composite checksums:** A composite checksum is calculated based on the individual checksums of each part in a multipart upload. Instead of computing a checksum based on all of the data content, this approach aggregates the part-level checksums (from the first part to the last) to produce a single, combined checksum for the complete object. You may only use the composite checksum type with certain checksum algorithms and only when using a multipart upload to upload your object. For the algorithms that support each checksum type, see the [Multipart uploads](#MultipartUploads-Checksums) section. 
**Note**  
When an object is uploaded as a multipart upload, the entity tag (ETag) for the object is not an MD5 digest of the entire object. Instead, Amazon S3 calculates the MD5 digest of each individual part as it is uploaded. The MD5 digests are used to determine the ETag for the final object. Amazon S3 concatenates the bytes for the MD5 digests together and then calculates the MD5 digest of these concatenated values. During the final ETag creation step, Amazon S3 adds a dash with the total number of parts to the end.

### Single part uploads
<a name="SinglePartUploads-Checksums"></a>

Checksums of objects that are uploaded in a single part (using [`PutObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html#API_PutObject)) are treated as full object checksums. When you upload an object in the Amazon S3 console, you can choose the checksum algorithm that you want S3 to use and also (optionally) provide a precomputed value. Amazon S3 then validates the precomputed checksum value before storing the object and its checksum value. You can verify an object's data integrity when you request the checksum value during object downloads.

### Multipart uploads
<a name="MultipartUploads-Checksums"></a>

When you upload the object in multiple parts using the [`MultipartUpload`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_MultipartUpload.html) API, you can specify the checksum algorithm that you want Amazon S3 to use and the checksum type (full object or composite). 

 The following table indicates which checksum algorithm type is supported for each checksum algorithm in a multipart upload:


| Checksum algorithm | Full object | Composite | 
| --- | --- | --- | 
| CRC-64/NVME (CRC64NVME) | Yes | No | 
| CRC-32 (CRC32) | Yes | Yes | 
| CRC-32C (CRC32C) | Yes | Yes | 
| SHA-1 (SHA1) | No | Yes | 
| SHA-256 (SHA256) | No | Yes | 
| MD5 (MD5) | No | Yes | 
| XXHash64 (XXHASH64) | No | Yes | 
| XXHash3 (XXHASH3) | No | Yes | 
| XXHash128 (XXHASH128) | No | Yes | 
| SHA-512 (SHA512) | No | Yes | 

## Using full object checksums for multipart upload
<a name="Full-object-checksums"></a>

When creating or performing a multipart upload, you can use full object checksums for validation on upload. This means that you can provide the checksum algorithm for the [`MultipartUpload`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_MultipartUpload.html) API, simplifying your integrity validation tooling because you no longer need to track part boundaries for uploaded objects. You can provide the checksum of the whole object in the [`CompleteMultipartUpload`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html) request, along with the object size.

When you provide a full object checksum during a multipart upload, the AWS SDK passes the checksum to Amazon S3, and S3 validates the object integrity server-side, comparing it to the received value. Then, Amazon S3 stores the object if the values match. If the two values don’t match, S3 fails the request with a `BadDigest` error. The checksum of your object is also stored in object metadata that you use later to validate an object's data integrity.

For full object checksums, you can use CRC-64/NVME (`CRC64NVME`), CRC-32 (`CRC32`), or CRC-32C (`CRC32C`) checksum algorithms in S3. Full object checksums in multipart uploads are only available for CRC-based checksums because they can linearize into a full object checksum. This linearization allows Amazon S3 to parallelize your requests for improved performance. In particular, S3 can compute the checksum of the whole object from the part-level checksums. This type of validation isn’t available for other algorithms, such as SHA and MD5. Because S3 has default integrity protections, if objects are uploaded without a checksum, S3 automatically attaches the recommended full object CRC-64/NVME (`CRC64NVME`) checksum algorithm to the object.

**Note**  
To initiate the multipart upload, you can specify the checksum algorithm and the full object checksum type. After you specify the checksum algorithm and the full object checksum type, you can provide the full object checksum value for the multipart upload.

**Important**  
When using multipart uploads with the new checksum algorithms (MD5, XXHash3, XXHash64, XXHash128, SHA-512), you must specify the checksum algorithm in the `CreateMultipartUpload` request using the `x-amz-checksum-algorithm` header. If you provide a checksum value in the `CompleteMultipartUpload` request (for example, `x-amz-checksum-sha512`) without having specified the algorithm in `CreateMultipartUpload`, the request will fail with an `InvalidRequest` error.

**Note**  
For existing checksum algorithms (CRC32, CRC32C, SHA-1, SHA-256), if the algorithm is not specified in `CreateMultipartUpload`, any checksum header provided in `CompleteMultipartUpload` is currently accepted but not validated or stored with the object. We recommend always specifying the algorithm in `CreateMultipartUpload` to ensure your checksums are validated and stored.

## Using part-level checksums for multipart upload
<a name="Part-level-checksums"></a>

When objects are uploaded to Amazon S3, they can be uploaded as a single object or uploaded in parts with the multipart upload process. You can choose a **Checksum** type for your multipart upload. For multipart upload part-level checksums (or composite checksums), Amazon S3 calculates the checksum for each individual part by using the specified checksum algorithm. You can use [`UploadPart`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html) to provide the checksum values for each part. If the object that you try to upload in the Amazon S3 console is set to use the CRC-64/NVME (`CRC64NVME`) checksum algorithm and exceeds 16 MB, it is automatically designated as a full object checksum.

Amazon S3 then uses the stored part-level checksum values to confirm that each part is uploaded correctly. When each part’s checksum (for the whole object) is provided, S3 uses the stored checksum values of each part to calculate the full object checksum internally, comparing it with the provided checksum value. This minimizes compute costs since S3 can compute a checksum of the whole object using the checksum of the parts. For more information about multipart uploads, see [Uploading and copying objects using multipart upload in Amazon S3](mpuoverview.md) and [Using full object checksums for multipart upload](#Full-object-checksums).

When the object is completely uploaded, you can use the final calculated checksum to verify the data integrity of the object.

When uploading a part of the multipart upload, be aware of the following: 
+ To retrieve information about the object, including how many parts make up the entire object, you can use the [`GetObjectAttributes`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectAttributes.html) operation. With additional checksums, you can also recover information for each individual part that includes the part's checksum value.
+ For completed uploads, you can get an individual part's checksum by using the [`GetObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html) or [`HeadObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html) operations and specifying a part number or byte range that aligns with a single part. If you want to retrieve the checksum values for individual parts of multipart uploads that are still in progress, you can use [`ListParts`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListParts.html).
+ Because of how Amazon S3 calculates the checksum for multipart objects, the checksum value for the object might change if you copy it. If you're using an SDK or the REST API and you call [`CopyObject`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html), Amazon S3 copies any object up to the size limitations of the `CopyObject` API operation. Amazon S3 does this copy as a single action, regardless of whether the object was uploaded in a single request or as part of a multipart upload. With a copy command, the checksum of the object is a direct checksum of the full object. If the object was originally uploaded using a multipart upload, the checksum value changes even though the data doesn't.
+ Objects that are larger than the size limitations of the `CopyObject` API operation must use [multipart upload copy commands](https://docs.aws.amazon.com/AmazonS3/latest/userguide/CopyingObjectsMPUapi.html).
+ When you perform some operations using the AWS Management Console, Amazon S3 uses a multipart upload if the object is greater than 16 MB in size.

## Checksum methods
<a name="ChecksumMethods"></a>

After uploading objects, you can get the checksum value and compare it to a precomputed or previously stored checksum value of the same checksum algorithm type. The following examples show you which checksum calculation methods you can use to verify data integrity.

### Using the S3 console
<a name="CheckObjectIntegrityConsole"></a>

To learn more about using the console and specifying checksum algorithms to use when uploading objects, see [Uploading objects](upload-objects.md) and [Tutorial: Checking the integrity of data in Amazon S3 with additional checksums](https://aws.amazon.com/getting-started/hands-on/amazon-s3-with-additional-checksums/?ref=docs_gateway/amazons3/checking-object-integrity.html).

### Using the AWS SDKs
<a name="CheckObjectIntegritySDK"></a>

The following example shows how you can use the AWS SDKs to upload a large file with multipart upload, download a large file, and validate a multipart upload file, all by using SHA-256 for file validation.

------
#### [ Java ]

**Example: Uploading, downloading, and verifying a large file with SHA-256**  
For instructions on creating and testing a working sample, see [Getting Started](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/getting-started.html) in the AWS SDK for Java Developer Guide.  

```
    import software.amazon.awssdk.auth.credentials.AwsCredentials;
    import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
    import software.amazon.awssdk.core.ResponseInputStream;
    import software.amazon.awssdk.core.sync.RequestBody;
    import software.amazon.awssdk.regions.Region;
    import software.amazon.awssdk.services.s3.S3Client;
    import software.amazon.awssdk.services.s3.model.AbortMultipartUploadRequest;
    import software.amazon.awssdk.services.s3.model.ChecksumAlgorithm;
    import software.amazon.awssdk.services.s3.model.ChecksumMode;
    import software.amazon.awssdk.services.s3.model.CompleteMultipartUploadRequest;
    import software.amazon.awssdk.services.s3.model.CompleteMultipartUploadResponse;
    import software.amazon.awssdk.services.s3.model.CompletedMultipartUpload;
    import software.amazon.awssdk.services.s3.model.CompletedPart;
    import software.amazon.awssdk.services.s3.model.CreateMultipartUploadRequest;
    import software.amazon.awssdk.services.s3.model.CreateMultipartUploadResponse;
    import software.amazon.awssdk.services.s3.model.GetObjectAttributesRequest;
    import software.amazon.awssdk.services.s3.model.GetObjectAttributesResponse;
    import software.amazon.awssdk.services.s3.model.GetObjectRequest;
    import software.amazon.awssdk.services.s3.model.GetObjectResponse;
    import software.amazon.awssdk.services.s3.model.GetObjectTaggingRequest;
    import software.amazon.awssdk.services.s3.model.ObjectAttributes;
    import software.amazon.awssdk.services.s3.model.PutObjectTaggingRequest;
    import software.amazon.awssdk.services.s3.model.Tag;
    import software.amazon.awssdk.services.s3.model.Tagging;
    import software.amazon.awssdk.services.s3.model.UploadPartRequest;
    import software.amazon.awssdk.services.s3.model.UploadPartResponse;
     
    import java.io.File;
    import java.io.FileInputStream;
    import java.io.FileOutputStream;
    import java.io.IOException;
    import java.io.InputStream;
    import java.io.OutputStream;
    import java.nio.ByteBuffer;
    import java.security.MessageDigest;
    import java.security.NoSuchAlgorithmException;
    import java.util.ArrayList;
    import java.util.Base64;
    import java.util.List;
     
    public class LargeObjectValidation {
        private static String FILE_NAME = "sample.file";
        private static String BUCKET = "sample-bucket";
        //Optional, if you want a method of storing the full multipart object checksum in S3.
        private static String CHECKSUM_TAG_KEYNAME = "fullObjectChecksum";
        //If you have existing full-object checksums that you need to validate against, you can do the full object validation on a sequential upload.
        private static String SHA256_FILE_BYTES = "htCM5g7ZNdoSw8bN/mkgiAhXt5MFoVowVg+LE9aIQmI=";
        //Example Chunk Size - this must be greater than or equal to 5MB.
        private static int CHUNK_SIZE = 5 * 1024 * 1024;
     
        public static void main(String[] args) {
            S3Client s3Client = S3Client.builder()
                    .region(Region.US_EAST_1)
                    .credentialsProvider(new AwsCredentialsProvider() {
                        @Override
                        public AwsCredentials resolveCredentials() {
                            return new AwsCredentials() {
                                @Override
                                public String accessKeyId() {
                                    return Constants.ACCESS_KEY;
                                }
     
                                @Override
                                public String secretAccessKey() {
                                    return Constants.SECRET;
                                }
                            };
                        }
                    })
                    .build();
            uploadLargeFileBracketedByChecksum(s3Client);
            downloadLargeFileBracketedByChecksum(s3Client);
            validateExistingFileAgainstS3Checksum(s3Client);
        }
     
        public static void uploadLargeFileBracketedByChecksum(S3Client s3Client) {
            System.out.println("Starting uploading file validation");
            File file = new File(FILE_NAME);
            try (InputStream in = new FileInputStream(file)) {
                MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
                CreateMultipartUploadRequest createMultipartUploadRequest = CreateMultipartUploadRequest.builder()
                        .bucket(BUCKET)
                        .key(FILE_NAME)
                        .checksumAlgorithm(ChecksumAlgorithm.SHA256)
                        .build();
                CreateMultipartUploadResponse createdUpload = s3Client.createMultipartUpload(createMultipartUploadRequest);
                List<CompletedPart> completedParts = new ArrayList<CompletedPart>();
                int partNumber = 1;
                byte[] buffer = new byte[CHUNK_SIZE];
                int read = in.read(buffer);
                while (read != -1) {
                    UploadPartRequest uploadPartRequest = UploadPartRequest.builder()
                            .partNumber(partNumber).uploadId(createdUpload.uploadId()).key(FILE_NAME).bucket(BUCKET).checksumAlgorithm(ChecksumAlgorithm.SHA256).build();
                    UploadPartResponse uploadedPart = s3Client.uploadPart(uploadPartRequest, RequestBody.fromByteBuffer(ByteBuffer.wrap(buffer, 0, read)));
                    CompletedPart part = CompletedPart.builder().partNumber(partNumber).checksumSHA256(uploadedPart.checksumSHA256()).eTag(uploadedPart.eTag()).build();
                    completedParts.add(part);
                    sha256.update(buffer, 0, read);
                    read = in.read(buffer);
                    partNumber++;
                }
                String fullObjectChecksum = Base64.getEncoder().encodeToString(sha256.digest());
                if (!fullObjectChecksum.equals(SHA256_FILE_BYTES)) {
                    //Because the SHA256 is uploaded after the part is uploaded; the upload is bracketed and the full object can be fully validated.
                    s3Client.abortMultipartUpload(AbortMultipartUploadRequest.builder().bucket(BUCKET).key(FILE_NAME).uploadId(createdUpload.uploadId()).build());
                    throw new IOException("Byte mismatch between stored checksum and upload, do not proceed with upload and cleanup");
                }
                CompletedMultipartUpload completedMultipartUpload = CompletedMultipartUpload.builder().parts(completedParts).build();
                CompleteMultipartUploadResponse completedUploadResponse = s3Client.completeMultipartUpload(
                        CompleteMultipartUploadRequest.builder().bucket(BUCKET).key(FILE_NAME).uploadId(createdUpload.uploadId()).multipartUpload(completedMultipartUpload).build());
                Tag checksumTag = Tag.builder().key(CHECKSUM_TAG_KEYNAME).value(fullObjectChecksum).build();
                //Optionally, if you need the full object checksum stored with the file; you could add it as a tag after completion.
                s3Client.putObjectTagging(PutObjectTaggingRequest.builder().bucket(BUCKET).key(FILE_NAME).tagging(Tagging.builder().tagSet(checksumTag).build()).build());
            } catch (IOException | NoSuchAlgorithmException e) {
                e.printStackTrace();
            }
            GetObjectAttributesResponse
                    objectAttributes = s3Client.getObjectAttributes(GetObjectAttributesRequest.builder().bucket(BUCKET).key(FILE_NAME)
                    .objectAttributes(ObjectAttributes.OBJECT_PARTS, ObjectAttributes.CHECKSUM).build());
            System.out.println(objectAttributes.objectParts().parts());
            System.out.println(objectAttributes.checksum().checksumSHA256());
        }
     
        public static void downloadLargeFileBracketedByChecksum(S3Client s3Client) {
            System.out.println("Starting downloading file validation");
            File file = new File("DOWNLOADED_" + FILE_NAME);
            try (OutputStream out = new FileOutputStream(file)) {
                GetObjectAttributesResponse
                        objectAttributes = s3Client.getObjectAttributes(GetObjectAttributesRequest.builder().bucket(BUCKET).key(FILE_NAME)
                        .objectAttributes(ObjectAttributes.OBJECT_PARTS, ObjectAttributes.CHECKSUM).build());
                //Optionally if you need the full object checksum, you can grab a tag you added on the upload
                List<Tag> objectTags = s3Client.getObjectTagging(GetObjectTaggingRequest.builder().bucket(BUCKET).key(FILE_NAME).build()).tagSet();
                String fullObjectChecksum = null;
                for (Tag objectTag : objectTags) {
                    if (objectTag.key().equals(CHECKSUM_TAG_KEYNAME)) {
                        fullObjectChecksum = objectTag.value();
                        break;
                    }
                }
                MessageDigest sha256FullObject = MessageDigest.getInstance("SHA-256");
                MessageDigest sha256ChecksumOfChecksums = MessageDigest.getInstance("SHA-256");
     
                //If you retrieve the object in parts, and set the ChecksumMode to enabled, the SDK will automatically validate the part checksum
                for (int partNumber = 1; partNumber <= objectAttributes.objectParts().totalPartsCount(); partNumber++) {
                    MessageDigest sha256Part = MessageDigest.getInstance("SHA-256");
                    ResponseInputStream<GetObjectResponse> response = s3Client.getObject(GetObjectRequest.builder().bucket(BUCKET).key(FILE_NAME).partNumber(partNumber).checksumMode(ChecksumMode.ENABLED).build());
                    GetObjectResponse getObjectResponse = response.response();
                    byte[] buffer = new byte[CHUNK_SIZE];
                    int read = response.read(buffer);
                    while (read != -1) {
                        out.write(buffer, 0, read);
                        sha256FullObject.update(buffer, 0, read);
                        sha256Part.update(buffer, 0, read);
                        read = response.read(buffer);
                    }
                    byte[] sha256PartBytes = sha256Part.digest();
                    sha256ChecksumOfChecksums.update(sha256PartBytes);
                    //Optionally, you can do an additional manual validation again the part checksum if needed in addition to the SDK check
                    String base64PartChecksum = Base64.getEncoder().encodeToString(sha256PartBytes);
                    String base64PartChecksumFromObjectAttributes = objectAttributes.objectParts().parts().get(partNumber - 1).checksumSHA256();
                    if (!base64PartChecksum.equals(getObjectResponse.checksumSHA256()) || !base64PartChecksum.equals(base64PartChecksumFromObjectAttributes)) {
                        throw new IOException("Part checksum didn't match for the part");
                    }
                    System.out.println(partNumber + " " + base64PartChecksum);
                }
                //Before finalizing, do the final checksum validation.
                String base64FullObject = Base64.getEncoder().encodeToString(sha256FullObject.digest());
                String base64ChecksumOfChecksums = Base64.getEncoder().encodeToString(sha256ChecksumOfChecksums.digest());
                if (fullObjectChecksum != null && !fullObjectChecksum.equals(base64FullObject)) {
                    throw new IOException("Failed checksum validation for full object");
                }
                System.out.println(fullObjectChecksum);
                String base64ChecksumOfChecksumFromAttributes = objectAttributes.checksum().checksumSHA256();
                if (base64ChecksumOfChecksumFromAttributes != null && !base64ChecksumOfChecksums.equals(base64ChecksumOfChecksumFromAttributes)) {
                    throw new IOException("Failed checksum validation for full object checksum of checksums");
                }
                System.out.println(base64ChecksumOfChecksumFromAttributes);
                out.flush();
            } catch (IOException | NoSuchAlgorithmException e) {
                //Cleanup bad file
                file.delete();
                e.printStackTrace();
            }
        }
     
        public static void validateExistingFileAgainstS3Checksum(S3Client s3Client) {
            System.out.println("Starting existing file validation");
            File file = new File("DOWNLOADED_" + FILE_NAME);
            GetObjectAttributesResponse
                    objectAttributes = s3Client.getObjectAttributes(GetObjectAttributesRequest.builder().bucket(BUCKET).key(FILE_NAME)
                    .objectAttributes(ObjectAttributes.OBJECT_PARTS, ObjectAttributes.CHECKSUM).build());
            try (InputStream in = new FileInputStream(file)) {
                MessageDigest sha256ChecksumOfChecksums = MessageDigest.getInstance("SHA-256");
                MessageDigest sha256Part = MessageDigest.getInstance("SHA-256");
                byte[] buffer = new byte[CHUNK_SIZE];
                int currentPart = 0;
                int partBreak = objectAttributes.objectParts().parts().get(currentPart).size();
                int totalRead = 0;
                int read = in.read(buffer);
                while (read != -1) {
                    totalRead += read;
                    if (totalRead >= partBreak) {
                        int difference = totalRead - partBreak;
                        byte[] partChecksum;
                        if (totalRead != partBreak) {
                            sha256Part.update(buffer, 0, read - difference);
                            partChecksum = sha256Part.digest();
                            sha256ChecksumOfChecksums.update(partChecksum);
                            sha256Part.reset();
                            sha256Part.update(buffer, read - difference, difference);
                        } else {
                            sha256Part.update(buffer, 0, read);
                            partChecksum = sha256Part.digest();
                            sha256ChecksumOfChecksums.update(partChecksum);
                            sha256Part.reset();
                        }
                        String base64PartChecksum = Base64.getEncoder().encodeToString(partChecksum);
                        if (!base64PartChecksum.equals(objectAttributes.objectParts().parts().get(currentPart).checksumSHA256())) {
                            throw new IOException("Part checksum didn't match S3");
                        }
                        currentPart++;
                        System.out.println(currentPart + " " + base64PartChecksum);
                        if (currentPart < objectAttributes.objectParts().totalPartsCount()) {
                            partBreak += objectAttributes.objectParts().parts().get(currentPart - 1).size();
                        }
                    } else {
                        sha256Part.update(buffer, 0, read);
                    }
                    read = in.read(buffer);
                }
                if (currentPart != objectAttributes.objectParts().totalPartsCount()) {
                    currentPart++;
                    byte[] partChecksum = sha256Part.digest();
                    sha256ChecksumOfChecksums.update(partChecksum);
                    String base64PartChecksum = Base64.getEncoder().encodeToString(partChecksum);
                    System.out.println(currentPart + " " + base64PartChecksum);
                }
     
                String base64CalculatedChecksumOfChecksums = Base64.getEncoder().encodeToString(sha256ChecksumOfChecksums.digest());
                System.out.println(base64CalculatedChecksumOfChecksums);
                System.out.println(objectAttributes.checksum().checksumSHA256());
                if (!base64CalculatedChecksumOfChecksums.equals(objectAttributes.checksum().checksumSHA256())) {
                    throw new IOException("Full object checksum of checksums don't match S3");
                }
     
            } catch (IOException | NoSuchAlgorithmException e) {
                e.printStackTrace();
            }
        }
    }
```

------

### Using the REST API
<a name="CheckObjectIntegrityREST"></a>

You can send REST requests to upload an object with a checksum value to verify the integrity of the data with [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html). You can also retrieve the checksum value for objects using [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html) or [HeadObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html).

### Using the AWS CLI
<a name="CheckObjectIntegrityCLI"></a>

You can send a `PUT` request to upload an object of up to 5 GB in a single operation. For more information, see the [`PutObject`](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-object.html#examples) in the *AWS CLI Command Reference*. You can also use [`get-object`](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html) and [`head-object`](https://docs.aws.amazon.com/cli/latest/reference/s3api/head-object.html) to retrieve the checksum of an already-uploaded object to verify the integrity of the data.

For information, see [Amazon S3 CLI FAQ](https://docs.aws.amazon.com/cli/latest/topic/s3-faq.html) in the *AWS Command Line Interface User Guide*. 

## Using Content-MD5 when uploading objects
<a name="checking-object-integrity-md5"></a>

Another way to verify the integrity of your object after uploading is to provide an MD5 digest of the object when you upload it. If you calculate the MD5 digest for your object, you can provide the digest with the `PUT` command by using the `Content-MD5` header. 

After uploading the object, Amazon S3 calculates the MD5 digest of the object and compares it to the value that you provided. The request succeeds only if the two digests match. 

Supplying an MD5 digest isn't required, but you can use it to verify the integrity of the object as part of the upload process.

## Using Content-MD5 and the ETag to verify uploaded objects
<a name="checking-object-integrity-etag-and-md5"></a>

The entity tag (ETag) for an object represents a specific version of that object. Keep in mind that the ETag only reflects changes to the content of an object, not changes to its metadata. If only the metadata of an object changes, the ETag remains the same. 

Depending on the object, the ETag of the object might be an MD5 digest of the object data:
+ If an object is created by the `PutObject`, `PostObject`, or `CopyObject` operation, or through the AWS Management Console, and that object is also plaintext or encrypted by server-side encryption with Amazon S3 managed keys (SSE-S3), that object has an ETag that is an MD5 digest of its object data.
+ If an object is created by the `PutObject`, `PostObject`, or `CopyObject` operation, or through the AWS Management Console, and that object is encrypted by server-side encryption with customer-provided keys (SSE-C) or server-side encryption with AWS Key Management Service (AWS KMS) keys (SSE-KMS), that object has an ETag that is not an MD5 digest of its object data.
+ If an object is created by either the multipart upload process or the `UploadPartCopy` operation, the object's ETag is not an MD5 digest, regardless of the method of encryption. If an object is larger than 16 MB, the AWS Management Console uploads or copies that object as a multipart upload, and therefore the ETag isn't an MD5 digest.

For objects where the ETag is the `Content-MD5` digest of the object, you can compare the ETag value of the object with a calculated or previously stored `Content-MD5` digest.

## Using trailing checksums
<a name="trailing-checksums"></a>

When uploading large objects to Amazon S3, you can either provide a precalculated checksum for the object or use an AWS SDK to automatically create trailing checksums for chunked uploads, on your behalf. If you use a trailing checksum, Amazon S3 automatically generates the checksum value by using your specified algorithm to validate the integrity of the object in chunked uploads, when you upload an object. 

To create a trailing checksum when using an AWS SDK, populate the `ChecksumAlgorithm` parameter with your preferred algorithm. The SDK uses that algorithm to calculate the checksum value for your object (or object parts) and automatically appends it to the end of your chunked upload request. This behavior saves you time because Amazon S3 performs both the verification and upload of your data in a single pass.

**Important**  
If you're using S3 Object Lambda, all requests to S3 Object Lambda are signed using `s3-object-lambda` instead of `s3`. This behavior affects the signature of trailing checksum values. For more information about S3 Object Lambda, see [Transforming objects with S3 Object Lambda](transforming-objects.md).

### Trailing checksum headers
<a name="trailing-checksums-headers"></a>

To make a chunked content encoding request, Amazon S3 requires client servers to include several headers to correctly parse the request. Client servers must include the following headers:
+ **`x-amz-decoded-content-length`:**This header indicates the plaintext size of the actual data that is being uploaded to Amazon S3 with the request.
+ **`x-amz-content-sha256`:** This header indicates the type of chunked upload that is included in the request. For chunked uploads with trailing checksums, the header value is `STREAMING-UNSIGNED-PAYLOAD-TRAILER` for requests that don’t use payload signing and `STREAMING-AWS4-HMAC-SHA256-PAYLOAD-TRAILER` for requests that use SigV4 payload signing. (For more information about implementing signed payloads, see [Signature calculations for the authorization header: Transferring a payload in multiple chunks](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html).)
+ **`x-amz-trailer`:** This header indicates the name of the trailing header in the request. If trailing checksums exist (where AWS SDKs append checksums to the encoded request bodies), the `x-amz-trailer` header value includes the `x-amz-checksum-` prefix and ends with the algorithm name. The following `x-amz-trailer` values are currently supported:
  + `x-amz-checksum-crc32`
  + `x-amz-checksum-crc32c`
  + `x-amz-checksum-crc64nvme`
  + `x-amz-checksum-sha1`
  + `x-amz-checksum-sha256`

**Note**  
You can also include the `Content-Encoding` header, with the chunked value, in your request. While this header isn’t required, including this header can minimize HTTP proxy issues when transmitting encoded data. If another `Content-Encoding` header (such as gzip) exists in the request, the `Content-Encoding` header includes the chunked value in a comma-separated list of encodings. For example, `Content-Encoding: aws-chunked, gzip`. 

### Chunked parts
<a name="trailing-checksums-chunks"></a>

When you upload an object to Amazon S3 using chunked encoding, the upload request includes the following types of chunks (formatted in the listed order):
+ **Object body chunks:** There can be one, multiple, or zero body chunks associated with a chunked upload request. 
+ **Completion chunks: ** There can be one, multiple, or zero body chunks associated with a chunked upload request. 
+ **Trailing chunks:** The trailing checksum is listed after the completion chunk. Only one trailing chunk is allowed.

**Note**  
 Every chunked upload must end with a final CRLF (such as `\r\n`) to indicate the end of the request. 

For examples of chunked formatting, see [Examples: Chunked uploads with trailing checksums](#example-chunked-uploads-trailing).

#### Object body chunks
<a name="trailing-checksums-object-body-chunks"></a>

Object body chunks are the chunks that contain the actual object data that is being uploaded to S3. These chunks have consistent size and format constraints.

##### Object body chunk size
<a name="trailing-checksums-object-body-chunks-size"></a>

These chunks must contain at least 8,192 bytes (or 8 KiB) of object data, except for the final body chunk, which can be smaller. There is no explicit maximum chunk size but you can expect all chunks to be smaller than the 5 GB maximum upload size. Chunk sizes can vary from one chunk to the next based on your client server implementation.

##### Object body chunk format
<a name="trailing-checksums-object-body-chunks-format"></a>

Object body chunks begin with the hexadecimal encoding of the number of bytes in the object body chunk, followed by a CRLF (Carriage Return Line Feed), the object bytes for that chunk, and another CRLF. 

For example:

```
{{hex-encoding-of-object-bytes-in-chunk}}\r\n
{{chunk-object-bytes}}\r\n
```

However, when the chunk is signed, the object body chunk follows a different format, where the signature is appended to the chunk size with a semicolon delimiter. For example:

```
{{hex-encoding-of-object-bytes-in-chunk}};{{chunk-signature}}\r\n
 {{chunk-object-bytes}}\r\n
```

For more information about chunk signing, see [Signature calculations for the Authorization Header: Transferring a payload in multiple chunks (AWS Signature Version 4)](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html). For more information about chunk formatting, see [Chunked transfer encoding](https://www.rfc-editor.org/rfc/rfc9112#name-chunked-transfer-coding) on the *RFC Editor* website.

#### Completion chunks
<a name="trailing-checksums-completion-chunks"></a>

Completion chunks are required to be the final object body chunk of every chunked upload. A completion chunk's format is similar to a body chunk, but always contains zero bytes of object data. (The zero bytes of object data indicate that all of the data has been uploaded.) Chunked uploads must include a completion chunk as its final object body chunk, following a format like this:

```
0\r\n
```

However, if the content encoding request uses payload signing, it follows this format instead:

```
0;{{chunk-signature}}\r\n
```

#### Trailer chunks
<a name="trailing-checksums-trailer-chunks"></a>

Trailer chunks hold the calculated checksum for all S3 upload requests. Trailer chunks include two fields: one header name field and one header value field. The header name field for an upload request must match the value passed into the `x-amz-trailer` request header. For example, if a request contains `x-amz-trailer: x-amz-checksum-crc32` and the trailer chunk has the header name `x-amz-checksum-sha1`, the request fails. The value field in the trailer chunk includes a base64 encoding of the big-endian checksum value for that object. (The big-endian ordering stores the most significant byte of data at the lowest memory address, and the least significant byte at the largest memory address). The algorithm used to calculate this checksum is the same as the suffix for the header name (for example, `crc32`). 

##### Trailer chunk format
<a name="trailing-checksums-trailer-chunk-format"></a>

Trailer chunks use the following format for unsigned payload requests:

```
x-amz-checksum-{{lowercase-checksum-algorithm-name}}:{{base64-checksum-value}}\n\r\n\r\n
```

For requests with [SigV4 signed payloads](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming-trailers.html), the trailer chunk includes a trailer signature after the trailer chunk. 

```
{{trailer-checksum}}\n\r\n
{{trailer-signature}}\r\n
```

You can also add the CRLF directly to the end of the base64 checksum value. For example:

```
x-amz-checksum-{{lowercase-checksum-algorithm-name}}:{{base64-checksum-value}}\r\n\r\n
```

#### Examples: Chunked uploads with trailing checksums
<a name="example-chunked-uploads-trailing"></a>

Amazon S3 supports chunked uploads that use `aws-chunked` content encoding for `PutObject` and `UploadPart` requests with trailing checksums.

**Example 1 – Unsigned chunked `PutObject` request with a trailing CRC-32 checksum**  

 The following is an example of a chunked `PutObject` request with a trailing CRC-32 checksum. In this example, the client uploads a 17 KB object in three unsigned chunks and appends a trailing CRC-32 checksum chunk by using the `x-amz-checksum-crc32` header.

```
PUT /Key+ HTTP/1.1
Host: {{amzn-s3-demo-bucket}}
Content-Encoding: aws-chunked
x-amz-decoded-content-length: {{17408}}
x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER
x-amz-trailer: x-amz-checksum-crc32

{{2000}}\r\n                                   // Object body chunk 1 (8192 bytes)
{{object-bytes}}\r\n
{{2000}}\r\n                                   // Object body chunk 2 (8192 bytes)
{{object-bytes}}\r\n
{{400}}\r\n                                    // Object body chunk 3 (1024 bytes)
{{object-bytes}}\r\n
{{0}}\r\n                                      // Completion chunk
x-amz-checksum-crc32:{{YABb/g==}}\n\r\n\r\n    // Trailer chunk (note optional \n character)
\r\n                                         // CRLF
```

Here's an example response:

```
HTTP/1.1 200
ETag: ETag
x-amz-checksum-crc32: YABb/g==
```

**Note**  
 The usage of the linefeed `\n` at the end of the checksum value might vary across clients.

**Example 2 – SigV4-signed chunked `PutObject` request with a trailing CRC-32 (`CRC32`) checksum**  

The following is an example of a chunked `PutObject` request with a trailing CRC-32 checksum. This request uses SigV4 payload signing. In this example, the client uploads a 17 KB object in three signed chunks. In addition to the `object body` chunks, the `completion chunk` and `trailer chunk` are also signed. 

```
PUT /Key+ HTTP/1.1
Host: {{amzn-s3-demo-bucket}}.s3.amazonaws.com
Content-Encoding: aws-chunked
x-amz-decoded-content-length: {{17408}}
x-amz-content-sha256: STREAMING-AWS4-HMAC-SHA256-PAYLOAD-TRAILER
x-amz-trailer: x-amz-checksum-crc32
		
{{authorization-code}}                            // SigV4 headers authorization

{{2000}};chunk-signature={{signature-value}}...\r\n   // Object body chunk 1 (8192 bytes)
{{object-bytes}}\r\n
{{2000}};{{chunk-signature}}\r\n                      // Object body chunk 2 (8192 bytes)
{{object-bytes}}\r\n
{{400}};{{chunk-signature}}\r\n                       // Object body chunk 3 (1024 bytes)
{{object-bytes}}\r\n
{{0}};{{chunk-signature}}\r\n                         // Completion chunk
x-amz-checksum-crc32:{{YABb/g==}}\n\r\n            // Trailer chunk (note optional \n character)
{{trailer-signature}}\r\n
\r\n                                           // CRLF
```

Here's an example response:

```
HTTP/1.1 200
ETag: ETag
x-amz-checksum-crc32: YABb/g==
```