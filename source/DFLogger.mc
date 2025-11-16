using Toybox.System as Sys;
using Toybox.Lang as Lang;

//! DataField 전용 간단한 로거
//! System.println()만 사용 (시뮬레이터에서 확인)
module DFLogger {

    //! 활동 시작 시 호출
    function reset() as Void {
        Sys.println("=== Activity Started ===");
    }

    //! 간단한 한 줄 로그 (System.println만)
    function log(msg as Lang.String) as Void {
        Sys.println(msg);
    }

    //! BLE 연결 상태 로그
    function logBle(event as Lang.String, detail as Lang.String) as Void {
        Sys.println("[BLE] " + event + ": " + detail);
    }

    //! 에러 로그
    function logError(source as Lang.String, error as Lang.String) as Void {
        Sys.println("[ERROR] " + source + ": " + error);
    }
}
