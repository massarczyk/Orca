// WPXMLRPCEncoder.m
//
// Copyright (c) 2013 WordPress - http://wordpress.org/
// Based on Eric Czarny's xmlrpc library - https://github.com/eczarny/xmlrpc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "WPXMLRPCEncoder.h"
#import "WPBase64Utils.h"
#import "WPStringUtils.h"

#pragma mark -

@implementation WPXMLRPCEncoder

@synthesize method = _method;
@synthesize parameters = _parameters;

- (id)init
{
    return [self initWithMethod:nil andParameters:nil];
}

- (id)initWithMethod:(NSString *)method andParameters:(NSArray *)parameters {
    self = [super init];
    if (self) {
        _method = method;
        _parameters = parameters;
    }
    
    return self;
}

- (id)initWithResponseParams:(NSArray *)params {
    self = [super init];
    if (self) {
        _parameters = params;
        _isResponse = YES;
    }
    return self;
}

- (id)initWithResponseFaultCode:(NSNumber *)faultCode andString:(NSString *)faultString {
    self = [super init];
    if (self) {
        _faultCode = faultCode;
        _faultString = faultString;
        _isResponse = YES;
        _isFault = YES;
    }
    return self;
}


#pragma mark - Public methods

- (NSData *)body {
    return [self dataEncodedWithError:nil];
}

- (NSData *)dataEncodedWithError:(NSError **) error {
    NSString * filePath = [self tmpFilePathForCache];
    if (![self encodeToFile:filePath error:error]){
        return nil;
    }

    NSData * encodedData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingUncached error:error];
    
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    
    return encodedData;
}

- (BOOL)encodeToFile:(NSString *)filePath error:(NSError **) error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    _streamingCacheFile = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:filePath] error:error];
    if (!_streamingCacheFile){
        return NO;
    }
    
    [self encodeForStreaming];
    
    return YES;
}

#pragma mark - Private methods

- (void)encodeForStreaming {
    [self appendString:@"<?xml version=\"1.0\"?>"];
    if (_isResponse) {
        [self appendString:@"<methodResponse>"];
        if (_isFault) {
            [self appendString:@"<fault>"];
            [self encodeDictionary:@{@"faultCode": _faultCode, @"faultString": _faultString}];
            [self appendString:@"</fault>"];
        } else {
            [self appendString:@"<params>"];
        }
    } else {
        [self appendString:@"<methodCall><methodName>"];
        [self encodeString:_method omitTag:YES];
        [self appendString:@"</methodName><params>"];
    }

    if (_parameters) {
        NSEnumerator *enumerator = [_parameters objectEnumerator];
        id parameter = nil;
        
        while ((parameter = [enumerator nextObject])) {
            [self appendString:@"<param>"];
            [self encodeObject:parameter];
            [self appendString:@"</param>"];
        }
    }

    if (_isResponse) {
        if (!_isFault) {
            [self appendString:@"</params>"];
        }
        [self appendString:@"</methodResponse>"];
    } else {
        [self appendString:@"</params>"];
        [self appendString:@"</methodCall>"];
    }

    [_streamingCacheFile synchronizeFile];
}

- (void)valueTag:(NSString *)tag value:(NSString *)value {
    [self appendFormat:@"<value><%@>%@</%@></value>", tag, value, tag];
}

- (void)encodeObject:(id)object {
    if (!object) {
        return;
    }
    
    if ([object isKindOfClass:[NSArray class]]) {
        [self encodeArray:object];
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        [self encodeDictionary:object];
    } else if (((__bridge CFBooleanRef)object == kCFBooleanTrue) || ((__bridge CFBooleanRef)object == kCFBooleanFalse)) {
        [self encodeBoolean:(CFBooleanRef)object];
    } else if ([object isKindOfClass:[NSNumber class]]) {
        [self encodeNumber:object];
    } else if ([object isKindOfClass:[NSString class]]) {
        [self encodeString:object omitTag:NO];
    } else if ([object isKindOfClass:[NSDate class]]) {
        [self encodeDate:object];
    } else if ([object isKindOfClass:[NSData class]]) {
        [self encodeData:object];
    } else if ([object isKindOfClass:[NSInputStream class]]) {
        [self encodeInputStream:object];
    } else if ([object isKindOfClass:[NSFileHandle class]]) {
        [self encodeFileHandle:object];
    } else {
        [self encodeString:object omitTag:NO];
    }
}

- (void)encodeArray:(NSArray *)array {
    NSEnumerator *enumerator = [array objectEnumerator];
    
    [self appendString:@"<value><array><data>"];
    
    id object = nil;
    
    while (object = [enumerator nextObject]) {
        [self encodeObject:object];
    }
    
    [self appendString:@"</data></array></value>"];
}

- (void)encodeDictionary:(NSDictionary *)dictionary {
    NSEnumerator *enumerator = [dictionary keyEnumerator];
    
    [self appendString:@"<value><struct>"];
    
    NSString *key = nil;
    
    while (key = [enumerator nextObject]) {
        [self appendString:@"<member>"];
        [self appendString:@"<name>"];
        [self encodeString:key omitTag:YES];
        [self appendString:@"</name>"];
        [self encodeObject:[dictionary objectForKey:key]];
        [self appendString:@"</member>"];
    }
    
    [self appendString:@"</struct></value>"];
}

- (void)encodeBoolean:(CFBooleanRef)boolean {
    if (boolean == kCFBooleanTrue) {
        [self valueTag:@"boolean" value:@"1"];
    } else {
        [self valueTag:@"boolean" value:@"0"];
    }
}

- (void)encodeNumber:(NSNumber *)number {
    NSString *numberType = [NSString stringWithCString:[number objCType] encoding:NSUTF8StringEncoding];

    if ([numberType isEqualToString:@"d"] || [numberType isEqualToString:@"f"]) {
        [self valueTag:@"double" value:[number stringValue]];
    } else {
        [self valueTag:@"i4" value:[number stringValue]];
    }
}

- (void)encodeString:(NSString *)string omitTag:(BOOL)omitTag {
    if (omitTag)
        [self appendString:[WPStringUtils escapedStringWithString:string]];
    else
        [self valueTag:@"string" value:[WPStringUtils escapedStringWithString:string]];
}

- (void)encodeDate:(NSDate *)date {
    unsigned components = kCFCalendarUnitYear | kCFCalendarUnitMonth | kCFCalendarUnitDay | kCFCalendarUnitHour | kCFCalendarUnitMinute | kCFCalendarUnitSecond;
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    [calendar setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    NSDateComponents *dateComponents = [calendar components:components fromDate:date];
    NSString *buffer = [NSString stringWithFormat:@"%.4d%.2d%.2dT%.2d:%.2d:%.2d%@", (int32_t)[dateComponents year], (int)[dateComponents month], (int)[dateComponents day], (int)[dateComponents hour], (int32_t)[dateComponents minute], (int32_t)[dateComponents second], @"Z", nil];
    
    [self valueTag:@"dateTime.iso8601" value:buffer];
}

- (void)encodeData:(NSData *)data {
    [self valueTag:@"base64" value:[WPBase64Utils encodeData:data]];
}

- (void)encodeInputStream:(NSInputStream *)stream {
    [self appendString:@"<value><base64>"];

    [WPBase64Utils encodeInputStream:stream withChunkHandler:^(NSString *chunk) {
        [self appendString:chunk];
    }];

    [self appendString:@"</base64></value>"];
}

- (void)encodeFileHandle:(NSFileHandle *)handle {
    [self appendString:@"<value><base64>"];

    [WPBase64Utils encodeFileHandle:handle withChunkHandler:^(NSString *chunk) {
        [self appendString:chunk];
    }];

    [self appendString:@"</base64></value>"];
}

- (void)appendString:(NSString *)aString {
    [_streamingCacheFile writeData:[aString dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)appendFormat:(NSString *)format, ... {
    va_list ap;
	va_start(ap, format);
	NSString *message = [[[NSString alloc] initWithFormat:format arguments:ap]autorelease];

    [self appendString:message];
}

- (NSString *)tmpFilePathForCache {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *directory = [paths objectAtIndex:0];
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    NSString * tmpPath = [directory stringByAppendingPathComponent:guid];
    return tmpPath;
}

@end
