/*
 * This program computes and displays all or part of the Mandelbrot 
 * set.  By default, it examines all points in the complex plane
 * that have both real and imaginary parts between -2 and 2.  
 * Command-line parameters allow zooming in on a specific part of
 * this range.
 * 
 * Usage:
 *   mandelbrot maxiter [x0 y0 size]
 * where 
 *   maxiter denotes the maximum number of iterations at each point
 *   x0, y0, and size specify the range to examine (a square 
 *     centered at x0 + iy0 of size 2*size by 2*size -- by default, 
 *     a square of size 4 by 4 centered at the origin)
 * 
 * Input:  none, except the optional command-line arguments
 * Output: a graphical display as described in Wilkinson & Allen,
 *   displayed using the X Window system, plus text output to
 *   standard output showing the above parameters, plus execution
 *   time in seconds.
 * 
 * 
 * Code originally code obtained from Web site for Wilkinson and Allen's
 * text on parallel programming:
 * http://www.cs.uncc.edu/~abw/parallel/par_prog/
 * 
 * Reformatted and revised by B. Massingill.
 * Rewritten for Mercantec MPI/CoE Cluster Computing Course by Paul Saunders.
 * 
 * Reformatted and merged with Mandelbrot CUDA by Kim Henriksen
 */
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <unistd.h>
#include <omp.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xos.h>
#define MPICH_SKIP_MPICXX
#include "/usr/include/mpich2/mpi.h"
//#include "/usr/lib/openmpi/include/mpi.h"
/* Functions for GUI */
#include "mandelbrot_guiV1.h"     /* has setup(), interact() */
#include "mandelbrot.h"     /* has setup(), interact() */


/* Default values for things. */
#define N           6          /* size of problem space (x, y from -N to N) */
#define NPIXELS     800         /* size of display window in pixels */
#define FIXED_ZOOM_FACTOR 3.0
#define DATA_TAG 1
#define CUDA_BLOCKS 32
#define CUDA_THREADS 128
#define MBROT_ITER 4096

int master_program(int nWorkers, int width, int height, int subBlockHeight, double real_min, double real_max, double imag_min, double imag_max, int maxiter);
int worker_program(int width, int height, double centre_x, double centre_y, double size, int total_pixel_height);

/* ---- Main program ---- */
int main(int argc, char *argv[]) {
    int nprocs;
    int myid;
    int returnval;

    int maxiter;
    double real_min = -N;
    double real_max = N;
    double imag_min = -N;
    double imag_max = N;
    double size;

    int width = NPIXELS; /* dimensions of display window */
    int height = NPIXELS;
    int centre_x = 0;

    if (MPI_Init(&argc, &argv) != MPI_SUCCESS) {
        fprintf(stderr, "MPI Initialisation Error\n");
        exit(EXIT_FAILURE);
    }
    MPI_Comm_size(MPI_COMM_WORLD, &nprocs);
    MPI_Comm_rank(MPI_COMM_WORLD, &myid);

    if (nprocs < 2) {
        fprintf(stderr, "Number of processes must be at least 2, but I only have %i\n", nprocs);
        MPI_Finalize();
        exit(EXIT_FAILURE);
    }

    /* Check command-line arguments */
    if ((argc < 3) || ((argc > 3) && (argc < 6))) {
        if (myid == 0) {
            fprintf(stderr, "usage:  %s maxiter block_size [x0 y0 size]\n", argv[0]);
        }
        MPI_Finalize();
        exit(EXIT_FAILURE);
    }

    if ((nprocs - 1) * atoi(argv[2]) > NPIXELS || NPIXELS % ((nprocs - 1) * atoi(argv[2])) != 0) {
        if (myid == 0) {
            fprintf(stderr, "%s%d%s%d%s", "Please ensure that the product of number of worker processes and block size is a divisor of ", NPIXELS, " and that the product is not greater than ", NPIXELS, "\n");
        }
        MPI_Finalize();
        exit(EXIT_FAILURE);
    }

    /* Process command-line arguments */
    maxiter = atoi(argv[1]);
    if (argc > 2) {
        double x0 = atof(argv[2]);
        double y0 = atof(argv[3]);
        size = atof(argv[4]);
        real_min = x0 - size;
        real_max = x0 + size;
        imag_min = y0 - size;
        imag_max = y0 + size;
    }

    // Divide image into chunks, which is equally great, one chunk for each node
    double image_block_size = size / (nprocs - 1);
    double centre_y = imag_min + image_block_size * (2 * myid - 1);

    unsigned int *data_msg = (unsigned int*) malloc((height * width) * sizeof (unsigned int));
    /* Call workers to do calculations, master to collect and display results */
    if (myid == 0) {
        returnval = master_program(nprocs - 1, width, height, image_block_size, real_min, real_max, imag_min, imag_max, maxiter);
    } else {
        returnval = worker_program(width, image_block_size, centre_x, centre_y, size, height);
    }

    /* Finish up */
    MPI_Finalize();

    return returnval;
}


int master_program(int nWorkers, int width, int height, int image_block_size, double real_min, double real_max, double imag_min, double imag_max, int maxiter) {
    Display *display;
    Window win;
    GC gc;
    long min_color, max_color;
    int setup_return;

    int start_row, end_row, current_row, iteration_count, ps;
    double start_time, end_time;

    int *data_msg = (int*) malloc(((image_block_size * width) + 2) * sizeof (int));

    MPI_Status status;

    int col;

    /* Initialize for graphical display */
    setup_return = setup(width, height, &display, &win, &gc, &min_color, &max_color);
    if (setup_return != 1) {
        fprintf(stderr, "Unable to initialize display, continuing\n");
    }
    /* (if not successful, continue but don't display results) */

    // Choose which events we want to handle   
    XSelectInput(display, win, ButtonPressMask | KeyPressMask);

    /*Start timing*/
    start_time = MPI_Wtime();

    /*Receive results from workers and draw points*/
    for (ps = 1; ps <= nWorkers; ps++) {
        MPI_Recv(data_msg, (image_block_size * width) + 2, MPI_INT, MPI_ANY_SOURCE, DATA_TAG, MPI_COMM_WORLD, &status);
        start_row = image_block_size * (nWorkers - 1);
        end_row = start_row + image_block_size - 1;

        for (current_row = start_row; current_row < end_row; current_row++) {
            for (col = 0; col < width; col++) {
                iteration_count = data_msg[((current_row - start_row) * width) + col];

                if (iteration_count < maxiter - 1) {
                    XSetForeground(display, gc, g_mapEntry[iteration_count % NUM_COLORS]);
                    //fprintf(stderr, "Plotting Row\n%d\n", current_row);
                    XDrawPoint(display, win, gc, col, current_row);
                } else {
                    XSetForeground(display, gc, g_mapEntry[0]);
                    XDrawPoint(display, win, gc, col, current_row);
                    //fprintf(stderr, "%d\n", iteration_count);
                }
            }
        }
    }

    /* Be sure all output is written */
    XFlush(display);

    end_time = MPI_Wtime();

    /*Produce text output*/
    double centre_real, centre_imag;
    centre_real = (real_max + real_min) / 2.0;
    centre_imag = (imag_max + imag_min) / 2.0;

    fprintf(stdout, "\n");
    fprintf(stdout, "MPI program\n");
    fprintf(stdout, "Number of worker processes = %d\n", nWorkers);
    fprintf(stdout, "centre = (%g, %g), size = %g\n", centre_real, centre_imag, (real_max - real_min) / 2);
    fprintf(stdout, "Maximum iterations = %d\n", maxiter);
    fprintf(stdout, "Execution Time in seconds = %g\n", end_time - start_time);
    fprintf(stdout, "\n");

    //double scale_real, scale_imag; 
    XEvent report;
    Window root_return, child_return;
    int root_x_return, root_y_return;
    int win_x_return, win_y_return;
    int j;
    unsigned int mask_return;

    //Compute scaling factors (for processing mouse clicks) 
    double scale_real = (double) (real_max - real_min) / (double) width;
    double scale_imag = (double) (imag_max - imag_min) / (double) height;

    //Event loop
    XNextEvent(display, &report);

    switch (report.type) {
        case ButtonPress:
            XQueryPointer(display, win, &root_return, &child_return, &root_x_return, &root_y_return, &win_x_return, &win_y_return, &mask_return);
            centre_real = real_min + ((double) win_x_return * scale_real);
            centre_imag = imag_min + ((double) (height - 1 - win_y_return) * scale_imag);
            fprintf(stderr, "coordinates = (%g, %g)\n", centre_real, centre_imag);
            fflush(stderr);

            fprintf(stderr, "%s\n", "Time to recalculate");
            return 1;

        case KeyPress:

            return 3;

    }

    free(data_msg);

    for (j = 0; j < NUM_COLORS; ++j) {
        XFreeColors(display, DefaultColormapOfScreen(DefaultScreenOfDisplay(display)), &g_mapEntry[j], 1, 0);
    }

    return 0;
}

int worker_program(int width, int height, double centre_x, double centre_y, double size, int total_pixel_height) {
    //unsigned int *img = malloc((height * width) * sizeof (unsigned int));
    unsigned int *data_msg = (unsigned int*) malloc((height * width) * sizeof (unsigned int));

    startCUDA(CUDA_BLOCKS, CUDA_THREADS, MBROT_ITER, centre_x, centre_y, size, data_msg, width, total_pixel_height, width, NPIXELS);
    //data_msg = (int*) img;
    MPI_Send(data_msg, (height * width), MPI_INT, 0, DATA_TAG, MPI_COMM_WORLD);

    return 2;
}
