# Pin of Microsoft.Data.SqlClient for the conversion tools

**Status:** [CONFIRMED] evidence from one run on a GitHub-hosted Windows runner; the pin below is [PROPOSED] until the owner or the reviewer applies it.
**Basis:** owner decision of 2026-10-05 ("Microsoft.Data.SqlClient, pode ser") in `docs/migration/catalog-conversion-plan.md`, section 5.
**Evidence:** `docs/phase1/evidence/sqlclient-pin-37314406178/report.json` (run 37314406178, workflow `sqlclient-pin`, script `spikes/sqlclient-pin/Invoke-SqlClientPin.ps1`).
Tags: [CONFIRMED] measured in the run; [PROPOSED] design proposal; [PENDING] open decision; [V] only verifiable on a real server.

## 1. Result

| Check | Result |
|---|---|
| Latest stable version on nuget.org (2026-10-05) | [CONFIRMED] 7.1.1 (published 09/29/2026 22:38:05); previous stable versions 7.0.1, 7.0.2, 7.0.3, 7.1.0 |
| Package SHA-256 (`.nupkg`, 6782596 bytes) | [CONFIRMED] `1da22a633fb44406d9a9400b00471039e8895ac3e717afe2e3beedba2f049e37` |
| Package SHA-512 equals the `packageHash` published in the NuGet catalog | [CONFIRMED] match (`uZ9oSxejHPjNn1sk2ZUlPnsTiKq0Kx3ApVHmk3ZeHMHyh2Wtikijp1h5J+QBQIHa5Cz92p0hstEfbX/3h/lUSw==`) |
| Package signature (`dotnet nuget verify --all`) | [CONFIRMED] valid, signed by Microsoft Corporation and countersigned by NuGet.org Repository by Microsoft |
| Licence | [CONFIRMED] MIT (authors: Microsoft) |
| Dependency closure (framework-dependent publish, net8.0, win-x64) | [CONFIRMED] 25 files including the native `Microsoft.Data.SqlClient.SNI.dll`; hashes in section 3 |
| Loads in the pinned PowerShell 7.6.6 (ZIP verified against `vendor/manifest.json`) on .NET 10.0.12 | [CONFIRMED] `Add-Type -Path` works, the assembly reports version 7.0.0.0, a connection string can be built |
| Read-only query against SQL Server through the pinned client | [CONFIRMED] against LocalDB `(localdb)\MSSQLLocalDB` (SQL Server 15.0.4382.1) with integrated security |

## 2. Proposed pin

[PROPOSED] entry for the tools (not for the portable application), to be added to `vendor/manifest.json` once PR #10 is merged, in a separate `tools` list:

```
name:        Microsoft.Data.SqlClient
version:     7.1.1
source:      https://api.nuget.org/v3-flatcontainer/microsoft.data.sqlclient/7.1.1/microsoft.data.sqlclient.7.1.1.nupkg
sha256:      1da22a633fb44406d9a9400b00471039e8895ac3e717afe2e3beedba2f049e37
sha512(b64): uZ9oSxejHPjNn1sk2ZUlPnsTiKq0Kx3ApVHmk3ZeHMHyh2Wtikijp1h5J+QBQIHa5Cz92p0hstEfbX/3h/lUSw==
licence:     MIT
runtime:     PowerShell 7.6.6 on .NET 10.0.12 (lib net8.0 assemblies load on .NET 10)
```

[PROPOSED] Pin the closure by the SHA-256 of each file (section 3), not by the SHA-256 of a ZIP: a ZIP built twice has different bytes (timestamps), so its hash is not stable. The tools verify every file of the closure before `Add-Type`.

## 3. Closure files (SHA-256 per file)

| File | File version | SHA-256 |
|---|---|---|
| `Microsoft.Bcl.Cryptography.dll` | 8.0.23.53103 | `30c625a2615dcf0a6b7b4355eac0b91d1ed7e3a8096cedc3d1b19b12f045b6f7` |
| `Microsoft.Data.SqlClient.dll` | 7.1.1.26272 | `3fc8292cfb9a22a5ed81e515584136f2c85c677ec49f6eb59fb282c0e99f20b6` |
| `Microsoft.Data.SqlClient.Extensions.Abstractions.dll` | 7.1.1.26272 | `7fa21b488a3569731b0230feb0e8f8779d22aa4f451c1e6264af51264af82510` |
| `Microsoft.Data.SqlClient.Internal.Logging.dll` | 7.1.1.26272 | `3a0d800c1ccbc41a427df0e84186488bfc1b5936bae6b5f6a732cb54877ac18f` |
| `Microsoft.Data.SqlClient.SNI.dll` | 7.1.0.0 | `e61ee1f20bb345147f85820b0d03c2b154bf9cd6b4971708114bb4782fd35b26` |
| `Microsoft.Extensions.Caching.Abstractions.dll` | 8.0.23.53103 | `31caebf834b6da88696a4a21ecb38eefff2623a531be925f6bd27719583ee3e2` |
| `Microsoft.Extensions.Caching.Memory.dll` | 8.0.1024.46610 | `a6bc869c530a2ed7573575dd61e40f0a1079ef6074251afe9701f927c5355ca8` |
| `Microsoft.Extensions.DependencyInjection.Abstractions.dll` | 8.0.1024.46610 | `67fa4325000db017dc0c35829b416f024f042d24efb868bcf17a895ee6500a93` |
| `Microsoft.Extensions.Logging.Abstractions.dll` | 8.0.1024.46610 | `45c22524218541717e4a0ade36847c1cda4921f5945b4975a1c78ddfe023d0b1` |
| `Microsoft.Extensions.Options.dll` | 8.0.224.6711 | `5e01894cbc0661bacb8ca8f485a40d5ee4e02f28fef58007668a0276431b4693` |
| `Microsoft.Extensions.Primitives.dll` | 8.0.23.53103 | `446ff16e903e7479558816e213a3adee9a1c1adad65a56d853801b10933e29d7` |
| `Microsoft.IdentityModel.Abstractions.dll` | 8.16.0.26043 | `c34d2ce8040d572d83762e5cf6cf2fe1e78d3de68d3bb9cebd793253f315f08d` |
| `Microsoft.IdentityModel.JsonWebTokens.dll` | 8.16.0.26043 | `cac7864ed8d14fe03ef7bbf8cc7fa0390d2e7b0af3472b8c1b1ba4c7c99b3086` |
| `Microsoft.IdentityModel.Logging.dll` | 8.16.0.26043 | `e5e606dbffd6ab4106d3058a046814f71fd96ac934f866a32aa0e10c00bb3e5a` |
| `Microsoft.IdentityModel.Protocols.dll` | 8.16.0.26043 | `8f4e850b00c9e881b7ca1753fb821b7e7cf999606d8091e4d98b411967e7f52c` |
| `Microsoft.IdentityModel.Protocols.OpenIdConnect.dll` | 8.16.0.26043 | `8e3fefb922ea84b9d242e07f7679bf6a733ae6cedac72e16fb2fc36f58e61dd1` |
| `Microsoft.IdentityModel.Tokens.dll` | 8.16.0.26043 | `7bc880d65d3dfa8c437822f200a1846a73bf589beb6ec9f802d2d529cb9218ba` |
| `Microsoft.SqlServer.Server.dll` | 1.0.0.0 | `a9dca1b42bc875f966b78b2c0880e62b838f0ed6567166d7f1f07ae4b76ec4bf` |
| `System.Configuration.ConfigurationManager.dll` | 8.0.1024.46610 | `f7ea3a9618aca48fb57fd06e9102b327ab66468ceb78c96d56f7d2eee2945983` |
| `System.Diagnostics.EventLog.dll` | 8.0.1024.46610 | `8343020e3752dc8fae7598816570aa30b041f835412a76dac7f65b229ed9532b` |
| `System.Diagnostics.EventLog.Messages.dll` | - | `dbfb7c81fb62a0bd3f77da92496640f179e96dd0c1a41a0d3c5d2a2445a3be46` |
| `System.IdentityModel.Tokens.Jwt.dll` | 8.16.0.26043 | `fd8ae62b01f008248bfff06c42d1514830e05cd6c01f807761d68a12f1b6dcda` |
| `System.Security.Cryptography.Pkcs.dll` | 8.0.1024.46610 | `d8e4b733fbaec1fe0e808fd6391479f190b170df03e309c5f07dc85445447d22` |
| `System.Security.Cryptography.ProtectedData.dll` | 8.0.23.53103 | `5e04d6cff3b6fe9706908970cd594861f0c08b3824f7827b2331b5f4fcee1bd1` |
| `System.Threading.RateLimiting.dll` | 8.0.23.53103 | `95b7e590ae833a7842bb8c0453032661e4110678248b0e43d26c39b2cc00716d` |

The native `Microsoft.Data.SqlClient.SNI.dll` is the win-x64 build selected by the publish step; an x86 or arm64 operator machine needs the matching native file [PENDING, the tools are assumed to run on win-x64 like the portable].

## 4. What this settles and what it does not

- [CONFIRMED] The GitHub Windows runner (`windows-2022`, image 20260927.320.1) carries SQL Server LocalDB. This answers the open question of the roadmap about SQL Server on runners: an integration test of the tools against a real SQL Server engine is possible in CI without any server of SISQUAL. Its default collation is `SQL_Latin1_General_CP1_CI_AS`, not the `Latin1_General_CI_AS` stated by the owner, so a test database must be created with the collation set explicitly.
- [CONFIRMED] The `.\SQLEXPRESS` and `localhost,1433` data sources did not answer on the runner; only LocalDB did.
- [PENDING] How the 25 files reach the operator machine: (a) a `tools/Initialize-SqlClient.ps1` that uses `dotnet publish` (needs the .NET SDK), (b) a ZIP attached to a GitHub release and verified file by file, or (c) the files kept outside Git on the operator machine. The owner decides.
- [PENDING] Connection security defaults: Microsoft.Data.SqlClient 4 and later encrypt by default and validate the server certificate. The probe used `TrustServerCertificate=true` for LocalDB only. The setting for the real SISQUAL servers is decided against a real server [V].
- [PENDING] Updating the pin: a new version needs a new run of the workflow and a review of the report.
- [V] The SQL Server path of `Export-ManagementEngines.ps1` and `Convert-ManagementDb.ps1` is still not exercised: this spike proves the client, not the tools. The natural next step is an integration test that creates a database with `Latin1_General_CI_AS` in LocalDB from the table shapes and runs both tools with `-SqlInstance`.
