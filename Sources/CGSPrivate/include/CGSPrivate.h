#ifndef CGSPRIVATE_H
#define CGSPRIVATE_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>

/* Private: maps an AXUIElement window to its CGWindowID.
   Resolves at link time against the ApplicationServices framework. */
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

/* Private CoreGraphics/SkyLight (CGS) window-Space queries. These resolve at
   link time against the system frameworks, like _AXUIElementGetWindow above.
   Used to tell whether a window lives on a Space other than the active one. */
typedef int CGSConnectionID;
typedef int CGSSpaceID;

enum {
    kCGSSpaceIncludesCurrent = 1 << 0,
    kCGSSpaceIncludesOthers  = 1 << 1,
    kCGSSpaceIncludesUser    = 1 << 2,
    kCGSAllSpacesMask = kCGSSpaceIncludesCurrent | kCGSSpaceIncludesOthers | kCGSSpaceIncludesUser,
};

CGSConnectionID CGSMainConnectionID(void);
CGSSpaceID CGSGetActiveSpace(CGSConnectionID cid);
CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs) CF_RETURNS_RETAINED;

#endif
