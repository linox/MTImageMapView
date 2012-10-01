//
//  MTImageMapView.m
//  ImageMap
//
//  Created by Almighty Kim on 9/29/12.
//  Copyright (c) 2012 Colorful Glue. All rights reserved.
//

#import "MTImageMapView.h"

#pragma mark MACRO
#pragma mark -

#ifdef DEBUG
    #define MTLOG(args...)	NSLog(@"%@",[NSString stringWithFormat:args])
    #define MTASSERT(cond,desc...)	NSAssert(cond, @"%@", [NSString stringWithFormat: desc])
    #define SAFE_DEALLOC_CHECK(__POINTER) { MTLOG(@"%@ dealloc",self); [super dealloc]; }
#else
    #define MTLOG(args...)
    #define MTASSERT(cond,desc...)
    #define SAFE_DEALLOC_CHECK(__POINTER) { [super dealloc]; }
#endif

#define ASSURE_DEALLOC(__POINTER) { [__POINTER release]; __POINTER = nil; }

#define IS_NULL_STRING(__POINTER) \
                        (__POINTER == nil || \
                        __POINTER == (NSString *)[NSNull null] || \
                        ![__POINTER isKindOfClass:[NSString class]] || \
                        ![__POINTER length])



#pragma mark - INTERFACES
#pragma mark -

#pragma  mark Debug View
#ifdef DEBUG_MAP_AREA
@interface MTMapDebugView : UIView
@property (nonatomic, assign) NSMutableArray *mapAreasToDebug;
@property (nonatomic)   CGPoint aTouchPoint;
@end
#endif

#pragma mark Map Area Model
@interface MTMapArea : NSObject
@property (nonatomic, retain)   UIBezierPath        *mapArea;
@property (nonatomic, readonly) NSUInteger          areaID;
-(id)initWithCoordinate:(NSString*)inStrCoordinate areaID:(NSInteger)inAreaID;
@end

#pragma mark Image Map View
@interface MTImageMapView()
@property (atomic, retain) NSMutableArray *mapAreas;
-(void)_finishConstructionWithImage:(UIImage *)inImage;
-(void)_performHitTestOnArea:(NSValue *)inTouchPoint;

#ifdef DEBUG_MAP_AREA
@property (nonatomic, assign) MTMapDebugView *viewDebugPath;
#endif

@end

#pragma mark - IMPLEMENTATIONS
#pragma mark -
#pragma mark Image Map View
@implementation MTImageMapView
{
    dispatch_semaphore_t	_concurrent_job_semaphore;
    id<MTImageMapDelegate>  _delegate;
}

@synthesize mapAreas;
@synthesize delegate = _delegate;

#ifdef DEBUG_MAP_AREA
@synthesize viewDebugPath;
#endif

-(id)initWithImage:(UIImage *)image
{
    self = [super initWithImage:image];
    if(self)
    {
        [self _finishConstructionWithImage:image];
    }
    return self;
}

-(id)initWithImage:(UIImage *)image highlightedImage:(UIImage *)highlightedImage
{
    self = [super initWithImage:image highlightedImage:highlightedImage];
    if(self)
    {
        [self _finishConstructionWithImage:image];
    }
    return self;
}

-(id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if(self)
    {
        [self _finishConstructionWithImage:self.image];
    }
    return self;
}


-(void)dealloc
{
#ifdef DEBUG_MAP_AREA
    self.viewDebugPath = nil;
#endif
    dispatch_release(_concurrent_job_semaphore);
    self.mapAreas = nil;
    self.delegate = nil;

	SAFE_DEALLOC_CHECK(self);
}

-(BOOL)canBecomeFirstResponder
{
    return YES;
}

// public methods
-(void)setMapping:(NSArray *)inMappingArea
        doneBlock:(void (^)(MTImageMapView *imageMapView))inBlockDone
{
    MTASSERT(inMappingArea != nil, @"mapping array cannot be nil");
    MTASSERT([inMappingArea count] != 0, @"mapping array should have element");
    
    dispatch_queue_t queue = \
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t main = dispatch_get_main_queue();

    NSUInteger countArea = [inMappingArea count];
    NSString* aStrArea = nil;
    
    self.mapAreas = nil;
    self.mapAreas = [NSMutableArray arrayWithCapacity:countArea];
    
#ifdef DEBUG_MAP_AREA
    [self.viewDebugPath setMapAreasToDebug:[self mapAreas]];
#endif

    for(NSUInteger index = 0; index < countArea; index++)
    {
        aStrArea = [inMappingArea objectAtIndex:index];
        
        dispatch_group_async(group,queue,^{
            
            // wait in line...
            dispatch_semaphore_wait(_concurrent_job_semaphore,
                                    DISPATCH_TIME_FOREVER);
            
            @autoreleasepool {
                                
                MTMapArea* anArea = \
                    [[MTMapArea alloc]
                     initWithCoordinate:aStrArea
                     areaID:index];

                [self.mapAreas addObject:anArea];
                
                [anArea release];
            }
            
            // notify semaphore for anothre job to kick in
            dispatch_semaphore_signal(_concurrent_job_semaphore);
            
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    if(inBlockDone != NULL)
    {
        dispatch_group_async(group, main, ^{
            inBlockDone(self);
        });
    }
    
	dispatch_release(queue);
    dispatch_release(group);
}

// private methods
-(void)_finishConstructionWithImage:(UIImage *)inImage
{
    CGSize imageSize = [inImage size];
    CGRect imageFrame = (CGRect){CGPointZero,imageSize};

    // set frame to size of image
    [self setFrame:imageFrame];
    
    //do not change width or height by aytoresizing
    UIViewAutoresizing sizingOption = [self autoresizingMask];
    UIViewAutoresizing sizingFilter = \
    (UIViewAutoresizingFlexibleWidth |
     UIViewAutoresizingFlexibleHeight) ^ (NSUInteger)(-1);
    sizingOption &= sizingFilter;
    [self setAutoresizingMask:sizingOption];
    
    int cpuCount = [[NSProcessInfo processInfo] processorCount];
    _concurrent_job_semaphore = dispatch_semaphore_create(cpuCount);
    
    [self setUserInteractionEnabled:YES];
    [self setMultipleTouchEnabled:NO];
    
#ifdef DEBUG_MAP_AREA
    self.viewDebugPath = \
    [[MTMapDebugView alloc]
     initWithFrame:imageFrame];
    [self.viewDebugPath setBackgroundColor:[UIColor clearColor]];
    [self addSubview:self.viewDebugPath];
    [self.viewDebugPath release];
#endif
}

-(void)_performHitTestOnArea:(NSValue *)inTouchPoint
{
    MTASSERT(inTouchPoint != nil, @"touch point is null");
    
    CGPoint     aTouchPoint     = [inTouchPoint CGPointValue];
    NSArray*    areaArray       = [self mapAreas];

    for(MTMapArea *anArea in areaArray)
    {
        if(CGPathContainsPoint(anArea.mapArea.CGPath,NULL,aTouchPoint,false))
        {
            if(_delegate != nil
               && [_delegate conformsToProtocol:@protocol(MTImageMapDelegate)]
               && [_delegate
                   respondsToSelector:
                   @selector(imageMapView:didSelectMapArea:)])
            {
                [_delegate
                 imageMapView:self
                 didSelectMapArea:anArea.areaID];
            }
            break;
        }
    }
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];

    // cancel previous touch ended event
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
	CGPoint touchPoint  = \
        [[touches anyObject] locationInView:self];

    NSValue*    touchValue =\
        [NSValue
         valueWithCGPoint:touchPoint];

    // perform new one
    [self
     performSelector:@selector(_performHitTestOnArea:)
     withObject:touchValue
     afterDelay:0.2];
    
#ifdef DEBUG_MAP_AREA
    [self.viewDebugPath setATouchPoint:touchPoint];
    [self.viewDebugPath setNeedsDisplay];
#endif
}
@end


#pragma  mark Debug View
#ifdef DEBUG_MAP_AREA
@implementation MTMapDebugView
@synthesize mapAreasToDebug = _mapAreasToDebug;
@synthesize aTouchPoint = _aTouchPoint;

- (void)drawRect:(CGRect)rect
{
	[super drawRect:rect];
    
    if(_mapAreasToDebug == nil || ![_mapAreasToDebug count])
        return;

	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSaveGState(context);
	// drawing path
	CGContextSetLineWidth(context, 1.0);
	UIColor *lineColor = [UIColor blueColor];
	CGContextSetStrokeColorWithColor(context, lineColor.CGColor);
	CGContextSetFillColorWithColor(context, lineColor.CGColor);
    
	CGContextDrawPath(context, kCGPathFillStroke);
	CGContextSetLineJoin(context,kCGLineJoinRound);
	CGContextSetLineCap(context,kCGLineCapButt);
	CGContextSetBlendMode(context,kCGBlendModePlusLighter);
    
	CGRect dotRect = \
        CGRectMake(_aTouchPoint.x - 3, _aTouchPoint.y - 3.0, 5.0, 5.0);
	CGContextAddEllipseInRect(context, dotRect);

    CGContextDrawPath(context, kCGPathStroke);
    for(MTMapArea *anArea in _mapAreasToDebug)
    {
        CGContextAddPath(context, anArea.mapArea.CGPath);
    }

	CGContextStrokePath(context);
	CGContextRestoreGState(context);
}
@end
#endif


#pragma mark Map Area Model
@implementation MTMapArea
{
    UIBezierPath        *_mapArea;
    NSUInteger          _areaID;
}
@synthesize mapArea         = _mapArea;
@synthesize areaID          = _areaID;

-(id)initWithCoordinate:(NSString*)inStrCoordinate areaID:(NSInteger)inAreaID
{
    self = [super init];
    
    if(self != nil)
    {
        // set area id
        _areaID = inAreaID;
        
        // create map area out of coordinate string
        MTASSERT(!IS_NULL_STRING(inStrCoordinate)
                 ,@"*** string must contain area coordinates ***");
        
        NSArray*    arrAreaCoordinates = \
        [inStrCoordinate componentsSeparatedByString:@","];
        
        NSUInteger  countTotal      = [arrAreaCoordinates count];
        NSUInteger  countCoord      = countTotal/2;
        BOOL        isFirstPoint    = YES;
        
        // # of coordinate must be in even numbers.
        //http://stackoverflow.com/questions/160930/how-do-i-check-if-an-integer-is-even-or-odd
        MTASSERT(!(countTotal % 2), @"total # of coordinates must be even. count %d",countCoord);
        MTASSERT((3 <= countCoord), @"At least, three dots to represent an area");
        
        // add points to bezier path
        UIBezierPath  *path         = [UIBezierPath new];
        
        for(NSUInteger i = 0; i < countCoord; i++)
        {
            NSUInteger index = i<<1;
            CGPoint aPoint = \
            CGPointMake([[arrAreaCoordinates
                          objectAtIndex:index] floatValue]
                        , [[arrAreaCoordinates
                            objectAtIndex:index+1] floatValue]);
            
            if(isFirstPoint)
            {
                [path moveToPoint:aPoint];
                isFirstPoint = NO;
            }
            
            [path addLineToPoint:aPoint];
            
        }
        
        [path closePath];
        
        self.mapArea = path;
        [path release];
    }
    return self;
}

-(void)dealloc
{
    self.mapArea = nil;
	SAFE_DEALLOC_CHECK(self);
}
@end