# Oncast 이용 조건과 소스 코드 안내

## 이용 조건

Oncast는 Abue Ammar의 [Tinycast](https://github.com/abue-ammar/tinycast)를 수정한 앱입니다.
Oncast의 수정 사항은 Sang Yeop Lim이 작성했으며, 앱은 GNU Affero General Public License
버전 3 이상(AGPL-3.0-or-later)으로 배포합니다.

이 라이선스에 따라 앱을 사용하고, 복사하고, 수정하고, 재배포할 수 있습니다. 유료 배포도
가능합니다. 수정본을 배포할 때는 저작권과 라이선스 고지를 유지하고, 해당 배포본의 소스 코드를
라이선스가 정한 방법으로 제공해야 합니다. 자세한 권리와 조건, 보증 제외 조항은 함께 제공한
[LICENSE](LICENSE) 전문을 확인해 주세요. 이 안내문은 별도의 이용 제한을 추가하지 않습니다.

## 같은 버전의 소스 받기

1. About 화면에 표시된 앱 버전과 빌드 번호를 확인합니다.
2. [Oncast 릴리스 페이지](https://github.com/gityeop/tinycast/releases)에서 해당 배포본을 선택합니다.
3. 배포 파일과 함께 제공되는 `Oncast-source-<식별자>.tar.gz`와 `.sha256` 파일을 받습니다.
   소스 압축파일에는 앱 소스, 빌드 스크립트, Excalidraw 연결 코드, 라이선스 문서가 들어 있습니다.
4. 압축을 풀고 `FORK.md`의 빌드 방법을 따릅니다. macOS 26 이상, Xcode 26, XcodeGen이 필요합니다.

일반 저장소 주소는 <https://github.com/gityeop/tinycast>입니다. 저장소의 최신 코드와 GitHub가
자동 생성하는 `Source code` 파일은 설치한 배포본과 다를 수 있으므로, 해당 배포본에 첨부한
`Oncast-source-…tar.gz`를 선택해 주세요.

개발 빌드는 아직 릴리스 페이지에 게시되지 않았을 수 있습니다. 개발 빌드를 전달받았다면
전달자에게 함께 생성된 소스 압축파일을 요청해 주세요. 공식 배포본에 소스 파일이 없거나
다운로드할 수 없다면 [이슈 페이지](https://github.com/gityeop/tinycast/issues)에 앱 버전과
빌드 번호를 적어 알려주세요.

## 함께 사용하는 오픈소스

- Excalidraw 편집기는 MIT 라이선스입니다. 저작권 표시와 라이선스 전문을 함께 제공합니다.
- React 등 포함된 라이브러리와 폰트에는 각각의 라이선스가 적용됩니다.
- 앱의 `Contents/Resources/NOTICE.md`에서 제3자 고지를 확인할 수 있습니다.
- Excalidraw와 관련 라이브러리, 폰트의 고지는 앱의
  `Contents/Resources/Excalidraw/THIRD-PARTY-LICENSES.txt`에 있습니다.

Oncast는 Excalidraw의 공식 제품이 아니며, 제휴나 보증을 의미하지 않습니다.

## English

Oncast is a modified version of Tinycast by Abue Ammar. Oncast modifications are copyright
2026 Sang Yeop Lim. The program is distributed under the GNU Affero General Public License,
version 3 or, at your option, any later version. See the accompanying LICENSE for the full
terms, including the warranty disclaimer. Bundled third-party components retain their own licenses.

For an official release, download its accompanying `Oncast-source-<identifier>.tar.gz` and
`.sha256` file from <https://github.com/gityeop/tinycast/releases>. Use the release matching the
version and build number in About. Follow FORK.md to build the extracted source. For an unpublished
development build, obtain the accompanying source archive from its distributor. Report missing
release source at <https://github.com/gityeop/tinycast/issues>, including the version and build number.
