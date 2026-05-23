// 자동 생성 파일 — build.sh 가 manifest.xml 의 iq:application version 에서 주입.
// 직접 수정 금지(빌드 시 덮어씌워짐). 버전 변경은 manifest.xml 에서만.
// (Monkey C 는 런타임에 자기 manifest version 을 못 읽어 빌드 타임 주입으로 동기화함.)
module AppVersion {
    const VALUE = "1.2.0";
}
