# 版本归档（Release archive）

这里是 Windows 发布物的不可变归档目录。每个归档目录都由版本号、文件名和
SHA-256 唯一定位；同一个哈希不会被覆盖，不同构建即使使用相同版本号也会进入
不同的哈希目录。

## 分类

- `user-satisfied`：用户明确确认满意的版本。当前已登记 2026-08-20 最终 UI
  版本（SHA-256 为 `DA6D5AF4…1C26E6`）；由于原始文件已不在可访问位置，目录中
  只保留记录，未伪造文件。
- `github-official`：已经正式发布到 GitHub Releases 的版本和文件。
- `historical-test`：开发过程中的测试包或历史构建。
- `current-working`：当前工作区生成的构建物，便于回溯和比对。
- `missing-record`：只有构建记录或哈希、但没有找到原始文件的版本。

完整清单在 [`catalog.json`](catalog.json)。清单中 `archiveAvailable` 为 `false`
时表示只找到了记录，不能当作可下载文件。

可用下面的只读脚本核对归档文件是否仍与清单中的 SHA-256 一致：

```powershell
.\verify-release-archive.ps1
```

## 归档命令

在项目目录运行：

```powershell
.\archive-release.ps1 `
  -ArtifactPath .\dist\DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe `
  -Version 1.0.6 `
  -Classification current-working
```

`build-windows.ps1` 在成功生成安装包后会自动调用同一脚本。若只是临时构建而
不想归档，可显式传入 `-SkipArchive`；正式构建不建议使用该选项。

脚本采用“先复制到临时目录、校验后移动”的方式，并且在发现同名哈希目录内容
不一致时直接失败，避免再次发生版本文件被覆盖的问题。

若只知道某次构建的哈希而找不到文件，应在 `catalog.json` 中保留一条
`archiveAvailable: false` 的记录，不要创建空文件或占位安装包。

## English

This directory is an immutable archive for Windows release artifacts. A folder is keyed
by version, classification and SHA-256. Existing bytes are never replaced; rebuilding
the same version creates a new hash folder.

The tracked [`catalog.json`](catalog.json) includes archived files as well as historical
hash-only records. `archiveAvailable: false` means that only the historical metadata was
found and no downloadable bytes are present locally.

Run `archive-release.ps1` directly to archive an artifact. `build-windows.ps1` archives
successful installers automatically. Use `-SkipArchive` only for an intentional temporary
build.

Run `verify-release-archive.ps1` to check every locally archived file against its recorded
SHA-256 and to detect an accidentally missing metadata file.
