#ifndef CGSPRIVATE_H
#define CGSPRIVATE_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>

/* Private: maps an AXUIElement window to its CGWindowID.
   Resolves at link time against the ApplicationServices framework. */
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

#endif
