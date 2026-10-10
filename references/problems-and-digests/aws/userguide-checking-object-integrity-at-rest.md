

# Checking object integrity for data at rest in Amazon S3
<a name="checking-object-integrity-at-rest"></a>

If you need to verify the content of datasets stored in Amazon S3, the S3 Batch Operations [Compute checksum](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-compute-checksums.html) operation calculates both full object or composite checksums for objects at rest. The **Compute checksum** operation uses Batch Operations to asynchronously calculate the checksum values for a group of objects and automatically generates a consolidated integrity report, without creating new copies of your data, or restoring or downloading any data.

With the **Compute checksum** operation, you can efficiently verify billions of objects with a single job request. For each **Compute checksum** job request, S3 calculates the checksum values, and includes it in an automatically generated integrity report (also known as a completion report). You can then use the completion report to validate the integrity of your dataset.

The **Compute checksum** operation works with any object stored in S3, regardless of storage class or object size. Whether you need to verify your objects as a data preservation best practice, or meet compliance requirements, the **Compute checksum** operation reduces the cost, time, and effort required for data validation by performing checksum calculations at rest. For information about **Compute checksum** pricing, see the **Management and insights** tab on [Amazon S3 pricing](https://aws.amazon.com/s3/pricing/).

Then, you can use the output of the generated completion report to compare against the checksum values that you’ve stored in your databases to verify that your datasets remain intact over time. This approach helps you maintain end-to-end data integrity for business and compliance needs. For example, you can use the **Compute checksum** operation to submit a list of stored objects in S3 Glacier storage classes for annual security audits. Additionally, the range of supported checksum algorithms allow you to maintain continuity with the algorithms that are used in your applications.

## Using supported checksum algorithms
<a name="using-additional-checksums-rest"></a>

For data at rest, you can calculate checksums, using any of the supported checksum algorithms:

All supported checksum algorithms support both the full object and composite checksum types, except CRC-64/NVME (`CRC64NVME`), which supports the full object checksum type only.
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

## Using **Compute checksum**
<a name="Compute-checksums"></a>

For objects stored in Amazon S3, you can use the **Compute checksum** operation with S3 Batch Operations to check the content of stored data at rest. You can [create a Compute checksum Batch Operations job](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-create-job.html) by using the Amazon S3 console, AWS Command Line Interface (AWS CLI), REST API, or AWS SDK. When the **Compute checksum** job finishes, you receive a completion report. For more information about how to use the completion report, see [Tracking job status and completion reports](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-status.html).

Before creating your **Compute checksum** job, you must create an S3 Batch Operations AWS Identity and Access Management (IAM) role to grant Amazon S3 permissions to perform actions on your behalf. You’ll need to grant permissions to read the manifest file and to write a completion report to the S3 bucket. For more information, see [Compute checksums](batch-ops-compute-checksums.md).

### Using the S3 console
<a name="Compute-checksum-console"></a>

**To use the **Compute checksum** operation**

1. Sign in to the AWS Management Console and open the Amazon S3 console at [https://console.aws.amazon.com/s3/](https://console.aws.amazon.com/s3/).

1. In the navigation bar, choose the name of the currently displayed AWS Region. Next, choose the Region in which you want to create your job.
**Note**  
For copy operations, you must create the job in the same Region as the destination bucket. For all other operations, you must create the job in the same Region as the objects in the manifest.

1. Choose **Batch Operations** on the left navigation pane of the Amazon S3 console.

1. Choose **Create job**.

1. View the AWS Region where you want to create your job.
**Note**  
For copy operations, you must create the job in the same Region as the destination bucket. For all other operations, you must create the job in the same Region as the objects in the manifest.

1. Under **Manifest format**, choose the type of manifest object to use.
   + If you choose **S3 inventory report (manifest.json)**, enter the path to the `manifest.json` object, and (optionally) the **Manifest object version ID** if you want to use a specific object version. Alternatively, you can choose **Browse S3** and choose the manifest JSON file, which auto populates all the manifest object field entries.
   + If you choose **CSV**, choose the Manifest location type, Then, either enter the path to a CSV-formatted manifest object or choose **Browse S3** to select a manifest object. The manifest object must follow the format described in the console. If you want to use a specific version of the manifest object, then you can also specify the object version ID.
   + If you choose **Create manifest using S3 Replication configuration**, a list of objects will be generated using the replication configuration and optionally saved to the destination you choose. When using a replication configuration to generate the manifest, the only operation that will be available is **Replicate**.

1. Choose **Next**.

1. Under **Operation**, choose the **Compute checksum** operation to calculate the checksums on all objects listed in the manifest. Choose the **Checksum type** and **Checksum function** for your job. Then, choose **Next**.

1. Fill out the information for **Configure additional options**, and then choose **Next**.

1. On the **Configure additional options** page, fill out the information for your **Compute checksum** job.
**Note**  
Under **Completion report**, make sure to confirm the acknowledgement statement. This acknowledgement statement confirms that you understand that the completion report contains checksum values, which are used to verify the integrity of data stored in Amazon S3. Therefore, the completion report should be shared with caution. Also, be aware that if you're creating a Compute checksum request and you specify an external account owner's bucket location to store your completion report, make sure to specify the AWS account ID of the external bucket owner.

1. Choose **Next**.

1. On the **Review** page, review and confirm your settings.

1. (Optional) If you need to make changes, choose **Previous** to go back to the previous page, or choose **Edit** to update a specific step.

1. After you've confirmed your changes, choose **Create job**.

**To list and monitor the progress of all **Compute checksum** requests**

1. Sign in to the AWS Management Console and open the Amazon S3 console at [https://console.aws.amazon.com/s3/](https://console.aws.amazon.com/s3/).

1. In the left navigation pane, choose **Batch Operations**.

1. On the **Batch Operations** page, you can review job details such as the job priority, job completion rate, and total objects.

1. If you want to manage or clone a specific **Compute checksum** job, choose the **Job ID** to review additional job information.

1. On the specific **Compute checksum** job page, review the job details.

Each batch operations job progresses through different [job statuses](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-status.html#batch-ops-job-status-table). You can also [enable AWS CloudTrail events](https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-cloudtrail-logging-for-s3.html) in the S3 console to receive alerts on any job state changes. For active jobs, you can review the running job and completion rate on the **Job details** page.

### Using the AWS SDKs
<a name="Compute-checksum-sdk"></a>

------
#### [ Java ]

**Example: Creating a **Compute checksum** job**  
The following example shows you how to create a **Compute checksum** job (as part of a **Create job** request), and how to specify a manifest:  

```
// Required parameters
String accountId = "{{111122223333}}";
String roleArn = "arn:aws:iam::{{111122223333}}:role/BatchOperations";
String manifestArn = "arn:aws:s3:::{{my_manifests/manifest}}.csv";
String manifestEtag = "{{60e460c9d1046e73f7dde5043ac3ae85}}";
String reportBucketArn = "arn:aws:s3:::{{amzn-s3-demo-completion-report-bucket}}";
String reportExpectedBucketOwner = "{{111122223333}}";
String reportPrefix = "{{demo-report}}";

// Job Operation
S3ComputeObjectChecksumOperation s3ComputeObjectChecksum = S3ComputeObjectChecksumOperation.builder()
    .checksumAlgorithm(ComputeObjectChecksumAlgorithm.{{CRC64}})
    .checksumType(ComputeObjectChecksumType.{{COMPOSITE}})
    .build();

JobOperation operation = JobOperation.builder()
    .s3ComputeObjectChecksum(s3ComputeObjectChecksum)
    .build();

// Job Manifest
JobManifestLocation location = JobManifestLocation.builder()
    .eTag(manifestEtag)
    .objectArn(manifestArn)
    .build();

JobManifestSpec spec = JobManifestSpec.builder()
    .format(JobManifestFormat.S3_BATCH_OPERATIONS_CSV_20180820)
    .fields(Arrays.asList(JobManifestFieldName.BUCKET, JobManifestFieldName.KEY))
    .build();

JobManifest manifest = JobManifest.builder()
    .location(location)
    .spec(spec)
    .build();

// Completion Report
JobReport report = JobReport.builder()
    .bucket({{reportBucketArn}})
    .enabled({{true}}) // Must be true
    .expectedBucketOwner({{reportExpectedBucketOwner}})
    .format({{JobReportFormat.REPORT_CSV_20180820}})
    .prefix({{reportPrefix}})
    .reportScope({{JobReportScope.ALL_TASKS}})
    .build();

// Create Job Request
CreateJobRequest request = CreateJobRequest.builder()
    .accountId({{accountId}})
    .confirmationRequired({{false}})
    .manifest({{manifest}})
    .operation({{operation}})
    .priority({{10}})
    .report({{report}})
    .roleArn({{roleArn}});

// Create the client
S3ControlClient client = S3ControlClient.builder()
    .credentialsProvider(new ProfileCredentialsProvider())
    .region(Region.{{US_EAST_1}})
    .build();

// Send the request
try {
    CreateJobResponse response = client.createJob(request);
    System.out.println(response);    
} catch (AwsServiceException e) {
    System.out.println("AwsServiceException: " + e.getMessage());
    throw new RuntimeException(e);
} catch (SdkClientException e) {
    System.out.println("SdkClientException: " + e.getMessage());
    throw new RuntimeException(e);
}
```

**Example: Viewing **Compute checksum** job details**  
The following example shows how you can specify a job ID to view the job details (such as the job completion rate) for a **Compute checksum** job request:  

```
DescribeJobRequest request = DescribeJobRequest.builder()
        .accountId("1234567890")
        .jobId("a16217a1-e082-48e5-b04f-31fac3a66b13")
        .build();
```

------

### Using the AWS CLI
<a name="Compute-checksum-cli"></a>

You can use the [create-job](https://docs.aws.amazon.com/cli/latest/reference/s3control/create-job.html) command to create a new batch operations job, and to provide the list of objects. Then, specify the checksum algorithm and checksum type, and the destination bucket where you want to save the **Compute checksum** report. The following example creates an S3 Batch Operations **Compute checksum** job by using an S3 generated manifest for the AWS account {{111122223333}}.

To use this command, replace the {{user input placeholders}} with your own information:

```
aws s3control create-job \
    --account-id {{111122223333}} \
    --manifest '{"Spec":{"Format":"{{S3BatchOperations_CSV_20180820}}","Fields":["Bucket","Key"]},"Location":{"ObjectArn":"arn:aws:s3:::{{my-manifest-bucket/manifest}}.csv","ETag":"{{e0e8bfc50e0f0c5d5a1a5f0e0e8bfc50}}"}}' \
    --manifest-generator '{
        "S3JobManifestGenerator": {
          "ExpectedBucketOwner": "{{111122223333}}",
          "SourceBucket": "arn:aws:s3:::{{amzn-s3-demo-source-bucket}}",
          "EnableManifestOutput": {{true}},
          "ManifestOutputLocation": {
            "ExpectedManifestBucketOwner": "{{111122223333}}",
            "Bucket": "arn:aws:s3:::{{amzn-s3-demo-manifest-bucket}}",
            "ManifestPrefix": "{{prefix}}",
            "ManifestFormat": "{{S3InventoryReport_CSV_20211130}}"
          },
          "Filter": {
            "CreatedAfter": "{{2023-09-01}}",
            "CreatedBefore": "{{2023-10-01}}",
            "KeyNameConstraint": {
              "MatchAnyPrefix": [
                "{{prefix}}"
              ],
              "MatchAnySuffix": [
                "{{suffix}}"
              ]
            },
            "ObjectSizeGreaterThanBytes": {{100}},
            "ObjectSizeLessThanBytes": {{200}},
            "MatchAnyStorageClass": [
              "STANDARD",
              "STANDARD_IA"
            ]
          }
        }
      }' \
    --operation '{"S3ComputeObjectChecksum":{"ChecksumAlgorithm":"{{CRC64NVME}}","ChecksumType":"{{FULL_OBJECT}}"}}' \
    --report '{"Bucket":"arn:aws:s3:::{{my-report-bucket}}","Format":"{{Report_CSV_20180820}}","Enabled":{{true}},"Prefix":"{{batch-op-reports}}/","ReportScope":"{{AllTasks}}","ExpectedBucketOwner":"{{111122223333}}"}' \
    --priority {{10}} \
    --role-arn arn:aws:iam::{{123456789012}}:role/{{S3BatchJobRole}} \
    --client-request-token {{6e023a7e-4820-4654-8c81-7247361aeb73}} \
    --description "{{Compute object checksums}}" \
    --region {{us-west-2}}
```

After you submit the **Compute checksum** job, you receive the job ID as a response and it appears on the S3 Batch Operations list page. Amazon S3 processes the list of objects and calculates checksums for each object. After the job finishes, S3 provides a consolidated **Compute checksum** report at the specified destination.

To monitor the progress of your **Compute checksum** job, use the [describe-job](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3control/describe-job.html) command. This command checks the status of the specified batch operations job. To use this command, replace the {{user input placeholders}} with your own information.

For example:

```
aws s3control describe-job --account-id {{111122223333}} --job-id {{1234567890abcdef0}}
```

To [obtain a list](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-list-jobs.html) of all **Active** and **Complete** batch operations jobs, see [Listing jobs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-list-jobs.html) or [list-jobs](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3control/list-jobs.html) in the *AWS CLI Command Reference*.

### Using the REST API
<a name="Compute-checksum-api"></a>

You can send REST requests to verify object integrity with **Compute checksum** using [CreateJob](https://docs.aws.amazon.com/AmazonS3/latest/API/API_control_CreateJob.html). You can monitor the progress of **Compute checksum** requests by sending REST requests to the [DescribeJob](https://docs.aws.amazon.com/AmazonS3/latest/API/API_control_DescribeJob.html) API operation. Each batch operations job progresses through the following statuses:
+ **NEW**
+ **PREPARING**
+ **READY**
+ **ACTIVE**
+ **PAUSING**
+ **PAUSED**
+ **COMPLETE**
+ **CANCELLING**
+ **FAILED**

The API response notifies you of the current job state.