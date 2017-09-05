//
//  ExceotionManager.m
//  TempPro
//
//  Created by LHJ on 2017/8/28.
//  Copyright © 2017年 LHJ. All rights reserved.
//

#import "ExceptionManager.h"
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>

#define FileDir  [NSString stringWithFormat:@"%@/ExceptionManager/", NSTemporaryDirectory()]
#define FilePath [NSString stringWithFormat:@"%@/Exception.txt", FileDir]

// ===================================================================================================
// ===================================================================================================
/** 获取APP相关信息 */
void saveInfoToFile(NSString *strInfo);

/** 获取十六进制地址 */
NSString* getHEXAddress(long long address)
{
    NSString *strResult = [NSString stringWithFormat:@"0x%02llx", address];
    return strResult;
}

/** 获取加载偏移地址
 Exception Backtrace 部分的地址（stack address）不能 查找出 dsym 文件中查出对应的代码，
 因为iOS很早之前就引入了ASLR（Address space layout randomization），ASDL机制会在app加载时根据load address动态加一个偏移地址slide address。所以在捕获错误地址stack address后，需要减去偏移地址才能得到正确的符号地址。 */
long long getSlide()
{
    long long slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (_dyld_get_image_header(i)->filetype == MH_EXECUTE) {
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    return slide;
}
NSString* getAppInfo()
{
    NSString *appInfo = [NSString stringWithFormat:@"App: %@ \nDevice: iOS %@ \nUDID: %@\n",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                         [UIDevice currentDevice].systemVersion,
                         [UIDevice currentDevice].identifierForVendor];
    return appInfo;
}
NSString* defaultDateFormatterWithFormatYYYYMMddHHmmss()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    }
    return [dateFormatter stringFromDate:[NSDate date]];
}
void uncaughtExceptionHandler (NSException *exception){
    //这里可以取到 NSException 信息
    NSString *strDate = defaultDateFormatterWithFormatYYYYMMddHHmmss();
    if(strDate == nil){
        strDate = @"";
    }
    long long sildeAddress = getSlide();
    NSString *strSildeAddress = getHEXAddress(sildeAddress);
    NSString *strSymbolAddress = @"";
    if(exception.callStackSymbols.count >= 3){
        NSString *strAddress = exception.callStackSymbols[3];
        if([strAddress isKindOfClass:[NSString class]] == YES){
            NSRange rangeStart = [strAddress rangeOfString:@"0x"];
            NSRange rangeEnd = [strAddress rangeOfString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(rangeStart.location, strAddress.length - rangeStart.location)];
            rangeStart.length = rangeEnd.location - rangeStart.location;
            NSString *strTemp = [strAddress substringWithRange:rangeStart];
            long long address = strtoul([strTemp UTF8String], 0, 16); // 十六进制转换为十进制
            long long value = address - sildeAddress;
            strSymbolAddress = getHEXAddress(value);
        }
    }
    
    NSString *strExceptionDescription = [NSString stringWithFormat:@"Exception: ( Time : %@ )\nname:%@ \n reason:%@ \n SildeAddress: %@\n SymbolAddress: %@\n callStackSymbols:\n%@ \n",
                                         strDate,
                                         exception.name,
                                         exception.reason,
                                         strSildeAddress,
                                         strSymbolAddress,
                                         (exception.callStackSymbols!=nil)?exception.callStackSymbols.description : @""];
    strExceptionDescription = [strExceptionDescription stringByAppendingString:getAppInfo()];
    strExceptionDescription = [strExceptionDescription stringByAppendingString:@"\n\n"];
    
    NSSetUncaughtExceptionHandler(NULL); // 取消监听
    saveInfoToFile(strExceptionDescription);
}
/** 把报错信息保存到文件里面 */
void saveInfoToFile(NSString *strInfo)
{
    if(strInfo == nil) { return; }
    
    NSString *strFileDir = FileDir;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:strFileDir] != YES){ // 文件夹不存在，新建
        BOOL bTemp = [fileManager createDirectoryAtPath:strFileDir withIntermediateDirectories:YES attributes:nil error:nil];
        if(bTemp != YES){ // 创建失败，退出
            return;
        }
    }
    
    NSString *strFilePath = FilePath;
    if([fileManager fileExistsAtPath:strFilePath] != YES){
        BOOL bTemp = [fileManager createFileAtPath:strFilePath contents:nil attributes:nil];
        if(bTemp != YES){ // 创建失败，退出
            return;
        }
    }
    NSFileHandle *fileHanlde = [NSFileHandle fileHandleForUpdatingAtPath:strFilePath];
    [fileHanlde seekToEndOfFile]; // 跳转到内容末位
    NSData *data = [strInfo dataUsingEncoding:NSUTF8StringEncoding];
    if(data == nil){ // 转换失败，退出
        [fileHanlde closeFile];
        return;
    }
    [fileHanlde writeData:data]; // 添加到末位
    [fileHanlde closeFile]; // 关闭文件
    fileHanlde = nil;
}

// ===================================================================================================
// ===================================================================================================
void handleSignalHandler(int signalValue){
    long long sildeAddress = getSlide();
    NSString *strSildeAddress = getHEXAddress(sildeAddress);
    NSString *strStackAddress = nil;
    NSString *strSymbolAddress = nil;
    
    NSString *executableFile = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleExecutableKey]; //获取项目名称
    
    NSString *strDate = defaultDateFormatterWithFormatYYYYMMddHHmmss();
    NSMutableString *muStrContent = [NSMutableString new];
    [muStrContent appendFormat:@"%@ - SignalHandler - %i  ： ( Time ：%@ ) \nSildeAddress - %@\n", executableFile, signalValue, strDate,strSildeAddress];
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    
    NSMutableString *muStrValue = [NSMutableString new];
    char** strs = backtrace_symbols(callstack, frames);
    for (int i = 0; i <frames; i+=1) {
        NSString *strTemp = [NSString stringWithUTF8String:strs[i]];
        if(strTemp == nil
            || [strTemp isEqualToString:@""] == YES) {
            continue;
        }
        [muStrValue appendFormat:@"%@\n", strTemp];
    }
    free(strs);
    if(strSymbolAddress != nil){
        [muStrContent appendFormat:@"SymbolAddress - %@\n" ,strSymbolAddress];
    }
    if(muStrValue != nil
        && [muStrValue isEqualToString:@""] != YES){
        [muStrContent appendString:muStrValue];
    }
    
    [muStrContent appendString:@"\n\n"];
    saveInfoToFile(muStrContent);
    
    // 把监听都置空
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    kill(getpid(), signalValue); // 这句话不能少，如果少了，那么APP会卡住
}
/** 打开Exception捕获的功能 */
void openExceptionManager()
{
    // 这里用Mach异常捕获的方式，这种方式可以获取crash的直观信息
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    /* 捕获Unix信号，这种方式捕获的信号比较难理解（只能获取int型的异常标记）*/
    signal(SIGABRT, handleSignalHandler); //注册程序由于abort()函数调用发生的程序中止信号
    signal(SIGILL, handleSignalHandler); //注册程序由于非法指令产生的程序中止信号
    signal(SIGSEGV, handleSignalHandler); //注册程序由于无效内存的引用导致的程序中止信号
    signal(SIGFPE, handleSignalHandler); //注册程序由于浮点数异常导致的程序中止信号
    signal(SIGBUS, handleSignalHandler); //注册程序由于内存地址未对齐导致的程序中止信号
    signal(SIGPIPE, handleSignalHandler); //程序通过端口发送消息失败导致的程序中止信号
}

/** 开始上传Exception捕获报告，上传地址在 UploadAddressForException 指定*/
void uploadExceptionReload(void(^completeBlock)(int result))
{
    if(UploadAddressForException == nil) { return; }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *strFilePath = FilePath;
    if([fileManager fileExistsAtPath:strFilePath] != YES){ // 文件不存在，退出
        return;
    }
    NSURL *fileURL = [NSURL fileURLWithPath:strFilePath];
    
    // LHJ测试
    NSString *strContent = [[NSString alloc] initWithData:[fileManager contentsAtPath:strFilePath] encoding:NSUTF8StringEncoding];;
    if(strContent == nil) { strContent = @""; }
    // ---------
    
//    UIAlertView *alertView =  [[UIAlertView alloc]initWithTitle:@"提示" message:strContent delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
//    [alertView show];
    
    NSURL *url = [NSURL URLWithString:UploadAddressForException];
    if(url == nil
       || url.absoluteURL == nil
       || url.baseURL == nil) {
        return;
    }
    NSURLSession *urlSession = [NSURLSession sharedSession];
    NSMutableURLRequest *muURLRequest = [NSMutableURLRequest requestWithURL:url];
//    [muURLRequest addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
//    [muURLRequest addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [muURLRequest setTimeoutInterval:100]; // 超时时间
    [muURLRequest setHTTPMethod:@"POST"];
    [muURLRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    
    NSURLSessionUploadTask *uploadTask = [urlSession uploadTaskWithRequest:muURLRequest fromFile:fileURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        int result = 0;
        if(error == nil){ // 上传成功， 则删除文件
            [fileManager removeItemAtPath:strFilePath error:nil];
            result = 1;
        }
        if(completeBlock != nil){
            completeBlock(result);
        }
    }];
    [uploadTask resume]; // 启动
}

