//
//  ExceotionManager.h
//  TempPro
//
//  Created by LHJ on 2017/8/28.
//  Copyright © 2017年 LHJ. All rights reserved.
//

#import <Foundation/Foundation.h>

static NSString *const UploadAddressForException = @"";

/** 打开Exception捕获的功能，出现Exception的时候会记录到本地文件，然后通过手动调用 uploadExceptionReload 方法上传文件 */
void openExceptionManager();

/** 开始上传Exception捕获报告，上传地址在 UploadAddressForException 指定*/
void uploadExceptionReload(void(^completeBlock)(int result));
