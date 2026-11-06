
## Introduction

This container is intended to be used for faster development and integration testing of the application. It is not intended to be used in production.
It includes a pre-built version of the application and all the dependencies required to run the application.
All tools required to build the application are also included in the container.

The Docker images are multi-arch (linux/amd64 and linux/arm64). On Apple Silicon Macs, the arm64 variant runs natively without emulation.

A container that mocks the required XCONF services is also included as a separate container within the same docker network.
The mock XCONF services are used to simulate the XCONF services that are required by the application.
Service will be available at `http://mockxconf:50050` .

In the current version mock WEBCONFIG services are not included.
An alternative utility is provided to mock a very similar setter commands that will set the IPC name space `Device.X_RDKCENTRAL-COM_T2.ReportProfilesMsgPack` with the same format as the actual WEBCONFIG service.

Utilities to set multiprofiles in JSON format will also be included in the container in the next release.
Until next release please use the following command to set the multiprofiles in JSON format.

```bash

rbuscli setvalues Device.X_RDKCENTRAL-COM_T2.ReportProfiles string ''

```


## Prerequisites
A working installation of Docker and Docker Compose is required to run this container.
Host machine should have relevant credentials to clone dependant repositories from rdkcentral github.

## Steps to build the container
1. Clone the repository to the host machine.
2. Change directory to the cloned repository's sub-directory `containers`.
3. Run the following command to build the container:
```
./build.sh
```

## Steps to run the container and mock services

### Pre-requisites
1. Ensure there is a directory named L2_CONTAINER_SHARED_VOLUME crated in home directory of the host machine.
2. If user desires to mount a different directory, please update the `docker-compose.yaml` file with the desired path.
3. Both containers mount the same directory to share the data between them and is available at `/mnt/L2_CONTAINER_SHARED_VOLUME` directory in the container.

From within same location where compose.yaml is available, run the following command to start the container:
```
docker-compose up
```

## Shared L2 coverage report

The repository-root `generate_l2_coverage_report.py` generates a Markdown report
for any module with C sources, Gherkin feature files, Python `test_*.py` files,
and an lcov tracefile. It requires Python 3.8 or newer and only the standard
library; Docker and lcov are not needed to generate the report from an existing
tracefile.

Check out this repository alongside the module repository. From their parent
directory, run:

```bash
python3 docker-device-mgt-service-test/generate_l2_coverage_report.py \
    --component "Remote Debugger" \
    --report-details remote_debugger/test/functional-tests/l2_coverage_details.json \
    --tracefile /tmp/coverage.info \
    --src-dir remote_debugger/src \
    --features-dir remote_debugger/test/functional-tests/features \
    --tests-dir remote_debugger/test/functional-tests/tests \
    --output remote_debugger/test/functional-tests/L2_Coverage.md
```

For other modules, change the component name and input/output paths. All five
path arguments are required; `--component` defaults to the source directory's
parent name. Directories are scanned recursively. Features map to tests with
the same relative directory and stem, adding `test_` when needed. Empty feature
and test directories are supported.

The report retains the full eight-section layout: executive summary, detailed
feature/test mapping (including excess tests and orphans), source coverage with
bars, per-behavior detail, gap analysis, recommendations, infrastructure notes,
and complete feature/test inventories. Only lcov records
matched to this module's C sources contribute to line totals. Source-relative
paths distinguish files with identical basenames; ambiguous paths are excluded.
Merge repeated lcov records with `lcov --add-tracefile` before reporting.
Function discovery is heuristic and includes conditional C definitions. Test
counts are not test results, and Scenario Outline examples and parametrized
cases are not expanded. Summary totals also include disabled-test estimates.

`--report-details` is optional. It reads a module-owned JSON object containing
Markdown lines for the hand-written sections, plus display metadata. It does
not replace measured coverage or test counts. RRD supplies its existing
assessments through `test/functional-tests/l2_coverage_details.json`; other
modules can supply their own file or omit the option. Without details, sections
4, 6 and 7 explicitly state that no module-specific content was supplied.

| JSON field | Type | Purpose |
|---|---|---|
| `component_id` | string | Component identifier in the header |
| `source_label` | string | Source directory display label |
| `test_suite` | string | Test suite display label |
| `target_coverage` | string | Functional coverage goal (default `~100%`) |
| `source_order` | array of strings | Preferred source-relative file order; newly discovered files follow |
| `behavior_detail` | array of Markdown lines | Section 4 assessments and subsections |
| `recommendations` | array of Markdown lines | Section 6 prioritized recommendations |
| `infrastructure_notes` | array of Markdown lines | Section 7 infrastructure tables and notes |

All fields are optional; unknown fields or invalid types fail generation.
The generator supplies the section headings. Module owners must review the
hand-written assessments when tests or implementation change; these are not
inferred from lcov and can become stale.

In GitHub Actions, add a checkout before invoking the same command:

```yaml
- uses: actions/checkout@v4
    with:
        repository: rdkcentral/docker-device-mgt-service-test
        ref: main
        path: docker-device-mgt-service-test
```

The explicit ref matches the RRD PR test while this tooling is on
`main`. Use that branch for local checkouts too; remove or update
the ref after the tooling is available on the shared repository's default branch.

When running in a container, mount both checkouts in the shared volume and use
their paths under `/mnt/L2_CONTAINER_SHARED_VOLUME`. No image rebuild is needed.

Run the reporter's focused tests from this repository's root:

```bash
python3 -m pytest -q test_generate_l2_coverage_report.py
```

## Logging inside individual application container
### Native Platform container
```
docker exec -it native-platform /bin/bash
```
### Webservices container
- The services are enabled with https support with selfsigned certificates.
- Selfsigned certificates are shared between the containers.
- Leveraging the capabilities of docker network, self-signed certificates are added to the trusted certificates of the container which makes the services accessible over https without any certificate warnings.


#### Services are available at 
`https://mockxconf:50051/dataLakeMock` ==> Data upload service
`https://mockxconf:50050/loguploader/getT2DCMSettings` ==> DCA settings service
`https://mockxconf:50052/firmwareupdate/getfirmwaredata` ==> Firmware Download xconf service
`https://mockxconf:50053/featureControl/getSettings` ==> RFC XConf service

- Data source for the services is available at `/etc/xconf/xconf-dcm-response.json` directory.
- Data source for the firmwareupdate services is available at `/etc/xconf/xconf-cdl-response.json` directory.
- Data source for RFC services is available at `/etc/xconf/xconf-rfc-response.json` directory.


#### Login to the container using the following command:
```
docker exec -it mockxconf /bin/bash
```

#### Steps for adding additional packages to the container
1. Add the required packages to the `Dockerfile` of the respective container.
   - For the native platform container, update the `Dockerfile` in the `native-platform` directory.
    - For the mock-xconf webservices container, update the `Dockerfile` in the `mock-xconf` directory.
2. Rebuild the container using the `build.sh` script.
3. Restart the container using the `docker-compose up` command.
4. Login to the container and verify the installation of the required packages.
5. Create a pull request with the changes.
6. Once the changes are merged, the new container will be built and deployed to registry in the next release.

#### Mockxconf Server (RDK-RRD-Test_1.0-signed.tar)
1. This archive (mockxconf/RDK-RRD-Test_1.0-signed.tar) contains all necessary files to download rdm packages from the mockxconf Server.
