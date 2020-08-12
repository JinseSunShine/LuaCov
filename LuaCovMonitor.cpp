#include "LuaCovMonitor.h"
#include "Guid.h"
#include "Engine.h"

DEFINE_LOG_CATEGORY(LogLuaCov);

#define SELF GetInstance();

TSharedPtr<LuaCovMonitor, ESPMode::ThreadSafe> LuaCovMonitor::sInstance = nullptr;

LuaCovMonitor * LuaCovMonitor::GetInstance()
{
    if (sInstance.IsValid() == false)
    {
        sInstance = MakeShareable(new LuaCovMonitor());
        sInstance->Init();
    }
    return sInstance.Get();
}

LuaCovMonitor::LuaCovMonitor()
{

}

LuaCovMonitor::~LuaCovMonitor()
{

}

void LuaCovMonitor::Init()
{

} 

bool filter_lua_api(const char* file_define, int line) {

    if (file_define == NULL)
        return true;
    if (strcmp(file_define, "=[C]") != 0 && line > 0)
        return false;
    return true;
}

static int l_debug_hook(lua_State* L)
{
    int nArgs = lua_gettop(L);  // 参数个数
    if (nArgs <= 0)
        return 0;
    
    if (!lua_isstring(L, 1))
        return 0;

    const char* callevent = lua_tostring(L, 1);

    int level = 2;      // 栈层次1:luacov, 2:测试执行的文件

    lua_settop(L, 0);
    
    lua_getfield(L, lua_upvalueindex(1), "initialized");    //获取 runner.initialized
    if (!lua_toboolean(L, -1))
        return 0;

    lua_pop(L, 1);

    lua_Debug ar;
    if (!lua_getstack(L, level - 1, &ar))
    {
        return 0;
    }
    lua_getinfo(L, "S", &ar);
    const char* filename = ar.source;
    int line = ar.linedefined;

    if (filter_lua_api(filename, line))
        return 0;

    //int32 Year, Month, Day, DayOfWeek;
    //int32 Hour, Minute, Second, Millisecond;
    //FPlatformTime::UtcTime(Year, Month, DayOfWeek, Day, Hour, Minute, Second, Millisecond);

    uint64 nCycles = FPlatformTime::Cycles();
    double Millisecond = FPlatformTime::ToMilliseconds64(nCycles);

    lua_getfield(L, lua_upvalueindex(1), "call_hookIN");
    lua_pushstring(L, filename);
    lua_pushinteger(L, line);
    //lua_pushinteger(L, evt);
    lua_pushstring(L, callevent);
    //lua_pushinteger(L, Second);
    lua_pushnumber(L, Millisecond);

    lua_call(L, 4, 0);

    return 0;
}

int LuaNewHook(lua_State* L)
{
    lua_settop(L, 1);   // table: runner
    lua_newtable(L);    // table: ignored_files
    lua_pushcclosure(L, l_debug_hook, 2);   // 创建闭包函数,提供给hook调用
    return 1;
}

int LuaCovMonitor::LuaHook(lua_State* L)
{
    lua_newtable(L);
    lua_pushcfunction(L, LuaNewHook);
    lua_setfield(L, -2, "new");
    return 1;
}

void LuaCovMonitor::UploadLuaCov(FString uploadUrl, FString jsonData, int interval, FString guid)
{
    UE_LOG(LogLuaCov, Log, TEXT("[LuaCovMonitor::Upload] uploadUrl = %s"), *uploadUrl);

    FAsyncTask<LuaCovTask> *task = new FAsyncTask<LuaCovTask>(uploadUrl, jsonData, interval, guid,
        LuaCovMonitor::UploadComplateDelegate::CreateThreadSafeSP(this, &LuaCovMonitor::OnUploadComplate));

    task->StartBackgroundTask();
}

void LuaCovMonitor::OnUploadComplate(bool success)
{
    UE_LOG(LogLuaCov, Log, TEXT("[LuaCovMonitor::OnUploadComplate] All Upload Done! success=%d"), (int)success);

    if (success)
    {
        GEngine->AddOnScreenDebugMessage(-1, 20.f, FColor::Green, FString::Printf(TEXT("LuaCov Upload All Done!!!")));
    }
}


#pragma region LuaCovTask

void LuaCovTask::DoWork()
{
    //mLuaCovGuid = GetNewLuaCovID();

    GEngine->AddOnScreenDebugMessage(-1, 20.f, FColor::Green, FString::Printf(TEXT("Start Upload LuaCov! interval=%d Guid=%s"),mLuaCovInterval,*mLuaCovGuid));

    UploadData("application/json", mJsonData);
}

FORCEINLINE TStatId LuaCovTask::GetStatId() const
{
    RETURN_QUICK_DECLARE_CYCLE_STAT(LuaCovTask, STATGROUP_ThreadPoolAsyncTasks);
}

FString LuaCovTask::GetNewLuaCovID()
{
    FString guid = FGuid::NewGuid().ToString();
    return guid;
}

void LuaCovTask::OnHttpRequestComplete(FHttpRequestPtr request, FHttpResponsePtr response, bool bWasSuccessful)
{
    UE_LOG(LogLuaCov, Log, TEXT("[HttpFileUploadRequest::HttpRequestComplete]"));
    if (request->OnProcessRequestComplete().IsBound())
    {
        request->OnProcessRequestComplete().Unbind();
    }

    FString responseAsString = TEXT("");
    int32 httpStatusCode = -1;

    IHttpResponse *resp = response.Get();
    if (resp)
    {
        responseAsString = resp->GetContentAsString();
        responseAsString.TrimEnd();
        httpStatusCode = resp->GetResponseCode();
    }

    mUploadIndex--;

    if (EHttpResponseCodes::IsOk(httpStatusCode))
    {
        GEngine->AddOnScreenDebugMessage(-1, 20.f, FColor::Green, FString::Printf(TEXT("%s Upload Done!"), *responseAsString));
    }
    else
    {
        mFailedNum++;
        GEngine->AddOnScreenDebugMessage(-1, 20.f, FColor::Red, FString::Printf(TEXT("%s Upload Fail!"), *responseAsString));
        UE_LOG(LogLuaCov, Log, TEXT("[BugRushTask::OnHttpRequestComplete] Upload BugRush Failed! response=%s"), *responseAsString);
        UE_LOG(LogLuaCov, Log, TEXT("[BugRushTask::OnHttpRequestComplete] success=%d, code=%d resp=%s"), (int)bWasSuccessful, (int)httpStatusCode, *responseAsString);
    }

    if (mUploadIndex <= 0)
    {
        mOnComplateDelegate.ExecuteIfBound(mFailedNum == 0);
    }
}

void LuaCovTask::UploadData(FString ContentType, FString FileData)
{
    TSharedPtr<IHttpRequest> mRequest = FHttpModule::Get().CreateRequest();
    mRequest->SetURL(mUploadUrl);
    mRequest->SetVerb(TEXT("POST"));
    mRequest->SetHeader(TEXT("Content-Type"), ContentType);
    mRequest->SetHeader(TEXT("LuaCovGuid"), mLuaCovGuid);
    mRequest->SetHeader(TEXT("Interval"), FString::FromInt(mLuaCovInterval));
    mRequest->SetContentAsString(FileData);

    mRequest->OnProcessRequestComplete().BindRaw(this, &LuaCovTask::OnHttpRequestComplete);
    mRequest->ProcessRequest();

    mUploadIndex++;
}

#pragma endregion
