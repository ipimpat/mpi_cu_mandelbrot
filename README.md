# Description
Mandlebrot, CUDA, MPI and X Window (use Xwing/Putty on Windows)

# Compile

`make clean && make -f makefile`

# Run
mpirun -np 5 -hostfile /path/to/hostfile mpi_cuda_mandelbrot
