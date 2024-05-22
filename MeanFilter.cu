%%writefile cudabasic.cu

#include <stdlib.h>
#include <stdio.h>

#include <string.h>

double time_h = 0;
double time_d = 0;

int numOfRounds = 1;

void meanFilter_h (unsigned char* raw_image, unsigned char* filtered_image, int img_width, int img_height, int window_size)
{
  int half_window = (window_size - 1) / 2;

  for (int i=0; i < img_height; i++)
  {
    for(int j=0; j < img_width; j++)
    {
      int left_limit, right_limit, top_limit, bottom_limit;

      if(j - half_window >= 0){
        left_limit = j-half_window;
      }else{
        left_limit = 0;
      }

            if(j + half_window <= img_width-1){
        right_limit = j + half_window;
      }else{
        right_limit = img_width-1;
      }

      if(i - half_window >= 0){
        top_limit = i - half_window;
      }else{
        top_limit = 0;
      }

            if(i + half_window <= img_height-1){
        bottom_limit = i + half_window;
      }else{
        bottom_limit = img_height-1;
      }

      double sum_r = 0, sum_g = 0, sum_b = 0;
      for(int k = top_limit; k <= bottom_limit; k++)
      {
        for(int m = left_limit; m <= right_limit; m++)
        {
           int index = (k * img_width + m) * 3;

                    // Accumulate the values of each color channel separately
                    sum_r += raw_image[index];
                    sum_g += raw_image[index + 1];
                    sum_b += raw_image[index + 2];
        }
      }
       int current_window_size = (bottom_limit - top_limit + 1) * (right_limit - left_limit + 1);

            // Calculate the mean value for each color channel
            filtered_image[(i * img_width + j) * 3] = sum_r / current_window_size;
            filtered_image[(i * img_width + j) * 3 + 1] = sum_g / current_window_size;
            filtered_image[(i * img_width + j) * 3 + 2] = sum_b / current_window_size;
    }
  }
}

__global__ void meanFilter_d (unsigned char* raw_image, unsigned char* filtered_image, int img_width, int img_height, int window_size)
{
  int j = blockIdx.x * blockDim.x + threadIdx.x;
    int i = blockIdx.y * blockDim.y + threadIdx.y;

  int half_window = (window_size - 1) / 2;

  if (i < img_height && j < img_width)
  {
    int left_limit, right_limit, top_limit, bottom_limit;

    if(j - half_window >= 0){
      left_limit = j-half_window;
    }else{
      left_limit = 0;
    }

        if(j + half_window <= img_width-1){
      right_limit = j + half_window;
    }else{
      right_limit = img_width-1;
    }

    if(i - half_window >= 0){
      top_limit = i - half_window;
    }else{
      top_limit = 0;
    }

        if(i + half_window <= img_height-1){
      bottom_limit = i + half_window;
    }else{
      bottom_limit = img_height-1;
    }

    double sumR = 0, sumG = 0, sumB = 0;
    int current_window_size = 0;

    for(int k = top_limit; k <= bottom_limit; k++)
    {
      for(int m = left_limit; m <= right_limit; m++)
      {
        // Calculate the indices for Red, Green, and Blue components
        int index = 3 * (k * img_width + m);
        sumR += raw_image[index];       // Red component
        sumG += raw_image[index + 1];   // Green component
        sumB += raw_image[index + 2];   // Blue component
        current_window_size++;
      }
    }
    // Calculate the average values for Red, Green, and Blue components
        unsigned char avgR = sumR / current_window_size;
        unsigned char avgG = sumG / current_window_size;
        unsigned char avgB = sumB / current_window_size;

        // Write the average values to the filtered image
        int output_index = 3 * (i * img_width + j);
        filtered_image[output_index] = avgR;       // Red component
        filtered_image[output_index + 1] = avgG;   // Green component
        filtered_image[output_index + 2] = avgB;   // Blue component
  }
}

void saveBitmap(const char* filename, int width, int height, unsigned char* imageData,unsigned char *info) {
    FILE* file = fopen(filename, "wb");
    if (file == NULL) {
        fprintf(stderr, "Error: Unable to open file %s for writing.\n", filename);
        exit(1);
    }

    printf("File %s opened successfully for writing.\n", filename);

    // Calculate padding bytes
    int padding = (4 - (width * 3) % 4) % 4;

    unsigned char fileHeader[138];
    memcpy(fileHeader, info, 138);

  
    // Write the file header
    fwrite(fileHeader, sizeof(unsigned char), 138, file);

    // Allocate memory for a single row including padding
    unsigned char* paddedRow = (unsigned char*)malloc(sizeof(unsigned char) * (width * 3 + padding));
    if (paddedRow == NULL) {
        fprintf(stderr, "Error: Unable to allocate memory for padded row.\n");
        fclose(file);
        exit(1);
    }

    fwrite(imageData, sizeof(unsigned char), width * height * 3, file);

    // Write padding bytes
    //unsigned char paddingData[4] = {0, 0, 0, 0};
    //for (int i = 0; i < padding; i++) {
    //    fwrite(paddingData, sizeof(unsigned char), 1, file);
   // }

    if (ferror(file)) {
          fprintf(stderr, "Error writing to file.\n");
          fclose(file);
          free(paddedRow);
          exit(1);
      }

    // Free allocated memory

    // Close the file
    fclose(file);
}


int main(int argc,char **argv)
{
    printf("Begin......\n");

  //get bitmap to a char array
    FILE* file = fopen("/content/drive/MyDrive/img_640.bmp", "rb");
    unsigned char info[138];
    fread(info, sizeof(unsigned char), 138, file);

    int width, height;
    memcpy(&width, info + 18, sizeof(int));
    memcpy(&height, info + 22, sizeof(int));

    int window_size = 3;

    int size = 3 * width * abs(height);
    unsigned char *inputImage = (unsigned char*)malloc(size * sizeof(unsigned char));
    unsigned char* result_image_data_d;
    unsigned char *result_image_data_h=(unsigned char*)malloc(size * sizeof(unsigned char));
    unsigned char *result_image_data_h1=(unsigned char*)malloc(size * sizeof(unsigned char));

    unsigned char* image_data_d;

    fread(inputImage, sizeof(unsigned char), size, file);
    fclose(file);

    int block_size = 32;
    int grid_size = width/block_size;

    dim3 dimBlock(block_size, block_size, 1);
    dim3 dimGrid(grid_size, grid_size, 1);

    for(int x = 0; x < numOfRounds; x += 1)
    {
        cudaMalloc((void **)&image_data_d,size*sizeof(unsigned char));
        cudaMalloc((void **)&result_image_data_d,size*sizeof(unsigned char));

        cudaMemcpy(image_data_d,inputImage,size*sizeof(unsigned char),cudaMemcpyHostToDevice);

        clock_t start_d=clock();
    //execution of GPU code
        meanFilter_d <<< dimGrid, dimBlock >>> (image_data_d, result_image_data_d, width, height, window_size);
        cudaDeviceSynchronize();


        cudaError_t error = cudaGetLastError();
        if(error!=cudaSuccess)
        {
            fprintf(stderr,"ERROR: %s\n", cudaGetErrorString(error) );
            exit(-1);
        }

        clock_t end_d = clock();

        cudaMemcpy(result_image_data_h, result_image_data_d, size * sizeof(unsigned char), cudaMemcpyDeviceToHost);

        saveBitmap("image1.bmp", width, height, result_image_data_h,info);

        clock_t start_h = clock();
    //executing CPU code
        meanFilter_h(inputImage, result_image_data_h1, width, height, window_size);
        clock_t end_h = clock();

        time_h += (double)(end_h-start_h)/CLOCKS_PER_SEC;
        time_d += (double)(end_d-start_d)/CLOCKS_PER_SEC;

        cudaFree(image_data_d);
        cudaFree(result_image_data_d);
    }

    printf("Average GPU execution time: %f\n",(time_d/numOfRounds));
    printf("Average CPU execution time: %f\n",(time_h/numOfRounds));
    printf("CPU/GPU time: %f\n",(time_h/time_d));

    return 0;
}


Output
Begin......
File image1.bmp opened successfully for writing.
Average GPU execution time: 0.001159
Average CPU execution time: 0.041736
CPU/GPU time: 36.010354
														
 								
Original Image



 							
Blurred Image
