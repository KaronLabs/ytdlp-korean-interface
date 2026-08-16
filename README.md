# ytdlp-interface

이 프로젝트는 [yt-dlp](https://github.com/yt-dlp/yt-dlp)를 위한 Windows GUI 인터페이스로, 기본적으로는 유튜브 다운로드용으로 설계되었습니다.  
v1.2부터는 유튜브 URL 외의 주소도 입력할 수 있어, `yt-dlp`가 지원하는 거의 모든 사이트를 이론적으로 다운로드할 수 있습니다.  
지원 사이트 목록은 [여기](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)를 참고하세요.

사용하려면 원하는 경로에 새 폴더를 만든 뒤 압축을 풀고 `ytdlp-interface.exe`를 실행하면 됩니다.

## 최신 버전 다운로드

64bit: https://github.com/ErrorFlynn/ytdlp-interface/releases/download/v2.19.0/ytdlp-interface.7z  

32bit: https://github.com/ErrorFlynn/ytdlp-interface/releases/download/v2.19.0/ytdlp-interface_x86.7z  

Windows 7 64bit: https://github.com/ErrorFlynn/ytdlp-interface/releases/download/v2.19.0/ytdlp-interface_win7.7z  

Windows 7 32bit: https://github.com/ErrorFlynn/ytdlp-interface/releases/download/v2.19.0/ytdlp-interface_x86_win7.7z


---

## 소스 빌드

이 프로젝트는 다음 네 가지 정적 라이브러리에 의존합니다.  
- [Nana C++ GUI library](https://github.com/cnjinhao/nana) v1.8 이상(작성 시점 기준 v1.8은 개발 중이므로 `develop-1.8` 브랜치 빌드 필요)  
- [libjpeg-turbo](https://github.com/libjpeg-turbo/libjpeg-turbo)  
- libpng  
- [bit7z](https://github.com/rikyoz/bit7z)

프로젝트에는 수정된 Nana 라이브러리가 `ytdlp-interface dependencies.7z`에 포함되어 있습니다.  
원본 라이브러리로 링크할 수도 있지만, 수정본에는 원본에 없는 기능/동작이 반영되어 있습니다(2024년 6월 기준).  
특히 수정본은 인터페이스 색상 체계의 일관성 유지와 시스템 배율 요소의 크기 스케일 조정 동작을 보장합니다.

프로그램은 또한 [JSON for modern C++](https://github.com/nlohmann/json)를 사용해 `yt-dlp.exe`로부터 미디어 정보를 가져오고 설정 파일을 읽고 쓰며, 이는 프로젝트에 포함된 헤더 파일(필요 시 최신 버전으로 교체 가능)입니다.

소스 빌드는 Visual Studio 2026 기준으로 진행합니다(없는 경우 Community Edition 무료판 사용 가능).  
먼저 `ytdlp-interface`와 같은 폴더에 `ytdlp-interface dependencies.7z`를 풀면, 같은 위치에 다음 폴더가 나란히 생성됩니다.  
`bit7z`, `libjpeg-turbo-3.1.2`, `libpng`, `nana`, `ytdlp-interface`

다음으로 의존성 라이브러리를 빌드해야 합니다.  
모든 라이브러리는 `.sln`이 있으나, libjpeg-turbo는 CMake를 사용합니다.  
Visual Studio 시작 화면에서 **Open a folder**로 `libjpeg-turbo-3.1.2`를 열고 `F7`로 빌드합니다.  
초기 구성은 `x64-Debug`만 존재하므로, 드롭다운의 **Manage configurations...**에서 필요한 구성을 추가하세요.

모든 의존성 빌드가 완료되면 ytdlp-interface 빌드가 가능해지며, 프로젝트 내 경로 설정은 이미 준비되어 있습니다.

---

<img width="822" height="682" alt="settings" src="https://github.com/user-attachments/assets/2bf18ef3-e3d7-4e4c-9641-01419e21a6aa" />

---

<img width="1002" height="735" alt="queue" src="https://github.com/user-attachments/assets/215bb101-fa44-4817-8fcb-2fc0e32c883e" />

---

<img width="1002" height="735" alt="output" src="https://github.com/user-attachments/assets/95fd8a51-9c1f-47c1-89fb-b07d6d4dcb60" />
