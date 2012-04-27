// mandelbrot.cu

// Calculate number of iterations required to make each point in Mandelbrot Set diverge and colour the corresponding pixel
// Tends to work faster with floats rather than doubles - but at the expense of "colour blocking" at lower resolutions

// Paul Saunders
// Mercantec
// 03/11-2011

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__device__ inline int calcMandelbrot(const double xPos, const double yPos, const int crunch)
{
    double y = yPos;
    double x = xPos;
    double yy = y * y;
    double xx = x * x;
    int i = crunch;

    while (--i && (xx + yy < 4.0f)) {
        y = x * y * 2.0f + yPos;
        x = xx - yy + xPos;
        yy = y * y;
        xx = x * x;
    }
    return i;
} // CalcMandelbrot - count down until iterations are used up or until the calculation diverges

/*
__device__ void RGB(int x, int y, unsigned char* m, int step, int iter_count)
{
  unsigned char *p;
  unsigned int rgb;
  p = ((unsigned char *) (m + step*x)+3*y);
  rgb = *p+((*(p+1))<<8)+((*(p+2))<<16);
  
  rgb = iter_count*2048;
  
  *p = (unsigned char) (rgb&0xff);
  *(p+1) = (unsigned char) ((rgb>>8)&0xff);
  *(p+2) = (unsigned char) ((rgb>>16)&0xff);
  return;
} //Use calculated iteration count to determine the colour for each pixel 
*/
__global__ void Count(unsigned int *img, int rows, int cols, int step, int max_iterations, double centre_x, double centre_y, double size, int image_size)
{
  double rowfac = ((double) rows)/gridDim.x;
  int rowstart = blockIdx.x*rowfac;
  int rowend = (blockIdx.x+1)*rowfac;
  double colfac = ((double) cols)/blockDim.x;
  int colstart = threadIdx.x*colfac;
  int colend = (threadIdx.x+1)*colfac;
  double left_edge = centre_x - size/2.0;
  double top_edge = centre_y - size/2.0;
  double pixel_step = size/image_size;
  unsigned int *p;
  for (int i=rowstart; i<rowend; i++)
    {
      for (int j=colstart; j<colend; j++)
      {
	p = (unsigned int*) img + ((step * i) + j);
        *p = (unsigned int) calcMandelbrot(left_edge + j * pixel_step, top_edge + i * pixel_step, max_iterations);
      }
    }
}  //Divide calculations between the requested number of blocks and threads, having used the matrix's geometry to determine the values input to the calculation for each pixel

void startCUDA(int blocks, int threads, int iterations, double centre_x, double centre_y, double size, unsigned int* img, int rows, int cols, int step, int image_size)
{
   if (img!=NULL)
   {
      dim3 dimBlock(threads, 1, 1);
	  dim3 dimGrid(blocks, 1, 1);
      
      unsigned int *CUDAimg;
      cudaMalloc((void**) &CUDAimg, rows*cols);
      cudaMemcpy(CUDAimg, img, rows*cols, cudaMemcpyHostToDevice);
      Count<<<dimGrid, dimBlock>>>(CUDAimg, rows, cols, step, iterations, centre_x, centre_y, size, image_size);
      cudaMemcpy(img, CUDAimg, rows*cols, cudaMemcpyDeviceToHost);
      cudaFree(CUDAimg);
   }
}  // Allocate sufficient memory for the whole image (@3 bytes per pixel), transfer it to the graphics card (host to device), start the calculation process and, when complete, transfer the memory (containing the calculated values) back to the host
