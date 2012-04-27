/*
 * GUI-related functions for Mandelbrot program (C version).
*/
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xos.h>
#include <stdlib.h>
#include <stdio.h>

/* Initialize for graphical display.  Width, height are dimensions of display, in pixels.*/

#define NUM_COLORS 2048

/*Setup colormap entries for use in drawing fractal*/

typedef unsigned long mapEntry;
mapEntry *g_mapEntry = NULL;

mapEntry *initialiseColorMap(Display *display, int screen)
{
	Screen *screen_ptr = DefaultScreenOfDisplay(display);
	
	XColor xcolor;
	mapEntry *colorArray;
	int colorIndex = 0;
	int i;
	/*Dynamically allocate array to hold indexes to colormap entries*/
	
	colorArray = (mapEntry*)malloc(NUM_COLORS * sizeof(mapEntry));
	
	/*Populate array with XColor instances and receive returned colormap indexes*/
	
	xcolor.pixel = 0;
	xcolor.red = 0;
	xcolor.green = 0;
	xcolor.blue = 0;
	xcolor.flags = DoRed|DoGreen|DoBlue;;
	
	XAllocColor(display, DefaultColormapOfScreen(screen_ptr), &xcolor);
	colorArray[colorIndex] = xcolor.pixel;
	colorIndex++;
			
	for(i = 1; i < NUM_COLORS; i++)
	{
		xcolor.pixel = 0;
		xcolor.red = 32678 - (i*32);
		xcolor.green = (i*128);
		xcolor.blue = 32768 + (i*32);
		xcolor.flags = DoRed|DoGreen|DoBlue;
		
		XAllocColor(display, DefaultColormapOfScreen(screen_ptr), &xcolor);
		colorArray[colorIndex] = xcolor.pixel;
		colorIndex++;
	}
	
	return colorArray;
}

int setup(int width, int height, Display **display, Window *win, GC *gc, long *min_color, long *max_color)
//int setup(int width, int height, Display **display, Window *win, GC *gc)
{
    /* Variables for graphical display */
    int x = 0, y = 0;                  /* window position */
    int border_width = 4;              /* border width in pixels */
    int disp_width, disp_height;       /* size of screen */
    int screen;                        /* which screen */

    char *window_name = "Mandelbrot Set", *disp_name = NULL;
    long valuemask = 0;
    XGCValues values;

    long white, black; /* white, black pixel values */
    
    XEvent report;

    /* Connect to Xserver */
    if ( (*display = XOpenDisplay (disp_name)) == NULL )
    {
        fprintf(stderr, "Cannot connect to X server %s\n", XDisplayName(disp_name));
        return 0;
    }

    /* Initialize for graphical display  */
    screen = DefaultScreen (*display);
    disp_width = DisplayWidth (*display, screen);
    disp_height = DisplayHeight (*display, screen);
    
    g_mapEntry = initialiseColorMap(*display, screen);
    
    *win = XCreateSimpleWindow (*display, RootWindow (*display, screen), x, y, width, height, border_width, BlackPixel (*display, screen), WhitePixel (*display, screen));
    
    XStoreName(*display, *win, window_name);
    *gc = XCreateGC (*display, *win, valuemask, &values); /* graphics context */
    white = WhitePixel (*display, screen);       /* color value for white */
    black = BlackPixel (*display, screen);       /* color value for black */   
      
    XSetBackground (*display, *gc, black);
    XSetForeground (*display, *gc, white);
    
    XMapWindow (*display, *win);
    XSync(*display, False);

    //Get min and max for range of color values -- assumed to be defined by "white", "black"
    *min_color = (white > black) ? black : white;
    *max_color = (white > black) ? white : black;

    /* Wait for keyboard input before starting program */
    fprintf(stderr, "Press any key (with focus in display) to start the program\n");
    fflush(stderr);

    /* Choose which events we want to handle */
    XSelectInput(*display, *win, KeyPressMask);

    /* Wait for event */
    XNextEvent(*display, &report);

    return 1;
}
