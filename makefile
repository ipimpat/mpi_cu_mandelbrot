MPICC           := /usr/local/cuda/bin/nvcc -lX11 -Xptxas -v 
MPI_INCLUDES    := /usr/include/mpich2
MPI_LIBS        := /usr/lib

%.o : %.cu 
	#$(MPICC) -o $@ -c $< 
	$(MPICC) -I$(MPI_INCLUDES) -o $@ -c $< 

mpi_cuda_mandelbrot :  mandelbrot.o mandelbrotV1.o
	$(MPICC) $(CFLAGS) -L$(MPI_LIBS) -lmpich -o $@ *.o 

clean : 
	rm -f *.o *~

all : mpi_cuda_mandelbrot
