//
//  StemThickness.m
//  StemThickness
//
//  Created by Georg Seifert on 20.03.21.
//Copyright © 2021 RafalBuchner. All rights reserved.
//

#import "StemThickness.h"
#import <GlyphsCore/GlyphsFilterProtocol.h>
#import <GlyphsCore/GSGlyphEditViewProtocol.h>
#import <GlyphsCore/GSFilterPlugin.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GSComponent.h>
#import <GlyphsCore/GSProxyShapes.h>
#import <GlyphsCore/GSCallbackHandler.h>
#import <GlyphsCore/NSString+BadgeDrawing.h>

NSPoint GSMiddlePointStem(NSPoint A, NSPoint B) {
	A.x = (A.x + B.x) * 0.5;
	A.y = (A.y + B.y) * 0.5;
	return A;
}

NSString *formatDistance(CGFloat d, CGFloat scale) {
	// calculates how value of thickness will be shown
	if (scale < 2) {
		return [NSString stringWithFormat:@"%d", (int)round(d)];
		// return "%i." % round(d) // use this instead if you really want the dot at the end, but I don't understand why --mekkablue
	}
	else if (scale < 3) {
		return [NSString stringWithFormat:@"%0.1f", d];
	}
	else if (scale < 10) {
		return [NSString stringWithFormat:@"%0.2f", d];
	}
	return [NSString stringWithFormat:@"%0.3f", d];
}

static NSColor *red = nil;
static NSColor *blue = nil;
static NSColor *pointColor = nil;

@implementation StemThickness {
	NSViewController <GSGlyphEditViewControllerProtocol> *_editViewController;
	id _lastNodePair;
	CGFloat _scale;
	NSPoint _layerOrigin;
}

+ (void)initialize {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		red  = [NSColor colorWithCalibratedRed:0.96 green:0.44 blue:0.44 alpha:1];
		blue = [NSColor colorWithCalibratedRed:0.65 green:0.63 blue:0.94 alpha:1];
		pointColor = [NSColor colorWithCalibratedRed:0.2 green:0.6 blue:0.6 alpha:0.7];
	});
}

- (instancetype)init {
	self = [super init];
	if (self) {
		// do stuff
	}
	return self;
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (NSString *)title {
	return NSLocalizedStringFromTableInBundle(@"Stem Thickness", nil, [NSBundle bundleForClass:[self class]], @"");
}

- (NSString *)keyEquivalent {
	return @"s";
}

- (NSEventModifierFlags)modifierMask {
	return NSEventModifierFlagControl;
}

- (void)drawForegroundWithOptions:(NSDictionary *)options {
	NSView <GSGlyphEditViewProtocol> *view = _editViewController.graphicView;
	_scale = view.scale; // scale of edit window
	GSFont *font = [_editViewController representedObject];
	CGFloat upm = font.unitsPerEm;
	if (_scale < 0.15 * 1000 / upm || _scale > 6.0 * 1000 / upm) {
		return;
	}
	NSPoint crossHairCenter = [view getActiveLocation:[NSApp currentEvent]];
	_layerOrigin = view.activePosition;

	GSLayer *layer = [view activeLayer];
	NSDictionary *closestData = [self calcClosestInfo:layer position:crossHairCenter];
	if (!closestData) {
		return;
	}
	GSLog(@"closestData %@", closestData);
	if (GSDistance(crossHairCenter, [closestData[@"onCurve"] pointValue]) > 35 / _scale) {
		_lastNodePair = nil;
		return;
	}
	[self drawCrossingsForData:closestData];
}

- (CGFloat)getHandleSize {
	/*
	 Returns the current handle size as set in user preferences.
	 */
	NSUInteger Selected = [NSUserDefaults.standardUserDefaults integerForKey:@"GSHandleSize"];
	if (Selected == 0) {
		return 5.0;
	}
	else if (Selected == 2) {
		return 10.0;
	}
	else {
		return 7.0;  // Regular
	}
}

- (void)drawPoint:(NSPoint)thisPoint size:(CGFloat)size color:(NSColor *)color {

	if (!color) {
		color = pointColor;
	}
	// from Show Angled Handles by MekkaBlue
	@try {
		[color set];
		NSRect myRect = NSMakeRect(thisPoint.x - size * 0.5, thisPoint.y - size * 0.5, size, size);
		NSBezierPath *seledinCircles = [NSBezierPath bezierPathWithOvalInRect:myRect];
		[seledinCircles fill];
	}
	@catch (NSException *exception) {
		NSLog(@"__drawPoint %@", exception);
	}
}

- (void)drawDashedStrokeA:(NSPoint)A b:(NSPoint)B {
	NSBezierPath *bez = [NSBezierPath bezierPath];
	bez.lineWidth = 0;
	CGFloat dash[] = {2.0, 2.0};
	[bez setLineDash:dash count:2 phase:0];
	[bez moveToPoint:A];
	[bez lineToPoint:B];
	[bez stroke];
}

// returns two or three objects
+(NSArray *)closestPointsTo:(NSPoint)closestPoint inPoints:(NSArray *)points {
	CGFloat prevDistanceSquared = 0;
	for (int i = 0; i != points.count; ++i) {
		NSPoint point = [points[i] pointValue];
		CGFloat distanceSquared = (point.x - closestPoint.x)*(point.x - closestPoint.x) + (point.y - closestPoint.y)*(point.y - closestPoint.y);
		if (i != 0 && distanceSquared > prevDistanceSquared) {
			// as the points are all on one line, and sorted, we know we would not find any closer points.
			// this means the previous one must be the closest
			if (i == 1) {
				return [points subarrayWithRange:NSMakeRange(0, 2)]; // the first two points
			}
			return [points subarrayWithRange:NSMakeRange(i-2, 3)]; // closest and two neighbours
		}
		prevDistanceSquared = distanceSquared;
	}
	return [points subarrayWithRange:NSMakeRange(points.count - 2, 2)]; // the last two points
}

- (void)drawCrossingsForData:(NSDictionary *)closestData {
	CGFloat HandleSize = [self getHandleSize];

	CGFloat zoomedHandleSize = HandleSize * 0.875;

	GSLayer *layer = closestData[@"layer"];
	NSPoint closestPoint = [closestData[@"onCurve"] pointValue];

	// returns list of intersections
	NSArray *crossPoints = [layer calculateIntersectionsStartPoint:[closestData[@"normal"] pointValue] endPoint:[closestData[@"minusNormal"] pointValue] decompose:NO];
	// note: the first and last objects in crossPoints are identical to the start and end points (or vice versa)

	if (crossPoints.count <= 2) {
		// no intersections found
		return;
	}
	// remove the first and last element:
	crossPoints = [crossPoints subarrayWithRange:NSMakeRange(1, crossPoints.count - 2)];
	crossPoints = [StemThickness closestPointsTo:closestPoint inPoints:crossPoints];
	
	NSPoint p0 = [crossPoints[0] pointValue];
	NSPoint p1 = [crossPoints[1] pointValue];
	CGFloat distance01 = GSDistance(p0, p1);
	[self showDistance:distance01 cross:p0 onCurve:p1 color:blue];
	if ( crossPoints.count == 3 ) {
		NSPoint p2 = [crossPoints[2] pointValue];
		CGFloat distance12 = GSDistance(p2, p1);
		[self showDistance:distance12 cross:p2 onCurve:p1 color:blue];
	}
}

- (void)showDistance:(CGFloat)d cross:(NSPoint)cross onCurve:(NSPoint)onCurve color:(NSColor *)color {
	cross = GSScalePoint(cross, _scale);
	cross = GSAddPoints(cross, _layerOrigin);
	onCurve = GSScalePoint(onCurve, _scale);
	onCurve = GSAddPoints(onCurve, _layerOrigin);
	CGFloat handleSize = [self getHandleSize];
	CGFloat zoomedHandleSize = handleSize * 0.875 * 0.75;
	NSString *distanceShowed = formatDistance(d, _scale);
	NSPoint thisDistanceCenter = GSMiddlePointStem(onCurve, cross);
	[color set];
	[self drawDashedStrokeA:onCurve b:cross];
	CGFloat fontSize = handleSize * 1.5 * pow(_scale, 0.1);
	[distanceShowed drawBadgeAtPoint:thisDistanceCenter size:fontSize color:NSColor.textColor backgroundColor:[color blendedColorWithFraction:0.8 ofColor:NSColor.textBackgroundColor] alignment:GSCenterCenter visibleInRect:NSMakeRect(NSNotFound, 0, 0, 0)];
	[self drawPoint:cross size:zoomedHandleSize color:color];
	[self drawPoint:onCurve size:zoomedHandleSize color:color];
}

- (void)mouseMoved:(NSNotification *)notification {
	[_editViewController redraw];
}

- (void)willActivate {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mouseMoved:) name:@"mouseMovedNotification" object:nil];
}

- (void)willDeactivate {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

+(NSPoint)closestPointToCursor:(NSPoint)cursor onLayer:(GSLayer *)layer {
	NSPoint closestPoint = NSMakePoint(CGFLOAT_MAX, CGFLOAT_MAX);
	CGFloat closestDist = CGFLOAT_MAX;
	for (GSPath *path in layer.paths) {
		CGFloat currPathTime; // just a dummy, result unused
		NSPoint currClosestPoint = [path nearestPointOnPath:cursor pathTime:&currPathTime];
		CGFloat currDist = GSDistance(currClosestPoint, cursor);
		if (currDist < closestDist) {
			closestDist = currDist;
			closestPoint = currClosestPoint;
		}
	}
	return closestPoint;
}

- (NSDictionary *)calcClosestInfo:(GSLayer *)layer position:(NSPoint)pt {
	@try {
		NSPoint closestPoint = [StemThickness closestPointToCursor:pt onLayer:layer];
		if ( closestPoint.x == CGFLOAT_MAX ) return nil;
		NSPoint direction = GSUnitVectorFromTo(pt, closestPoint);
		NSPoint closestPointNormal = GSAddPoints(pt, GSScalePoint(direction, 10000));
		NSPoint minusClosestPointNormal = GSAddPoints(pt, GSScalePoint(direction, -10000));
		return @{
			@"onCurve": @(closestPoint),
			@"normal": @(closestPointNormal),
			@"minusNormal": @(minusClosestPointNormal),
			@"layer": layer,
		};
	}
	@catch (NSException *exception) {
		NSLog(@"__calcClosestInfo: %@", exception);
	}
	return nil;
}

- (NSViewController <GSGlyphEditViewControllerProtocol>*)controller {
	return _editViewController;
}

- (void)setController:(NSViewController <GSGlyphEditViewControllerProtocol>*)Controller {
	// Use [self controller]; as object for the current view controller.
	_editViewController = Controller;
}

@end
