#include "cudaCamera.h"

namespace RT
{
    namespace CUDA
    {
        // Number of rays generated by single thread
        static constexpr int NumRaysPerThread = 16;

        __global__
        void SpawnPrimaryRaysKernel( const CameraData* pCamera, int hCount, int vCount, RayData* pRays )
        {
            // Get global invocation index
            const int threadId = blockIdx.x * blockDim.x + threadIdx.x;
            const int numPrevRays = threadId * NumRaysPerThread;

            int y_ind = numPrevRays / hCount;
            int x_ind = numPrevRays % hCount;
            int r_ind = y_ind * hCount + x_ind;

            const int numRaysToSpawn = min( (vCount * hCount) - r_ind, NumRaysPerThread );

            if( numRaysToSpawn <= 0 )
            {
                // Nothing to spawn in this invocation
                return;
            }

            // Camera properties
            const auto cameraOrigin = pCamera->Origin;
            const auto cameraDirection = pCamera->Direction;

            const auto right = pCamera->Up.Cross( cameraDirection );
            const auto up = cameraDirection.Cross( right );

            // Compute horizontal and vertical steps
            const auto vstep = up * tanf( pCamera->HorizontalFOV / vCount ) / pCamera->AspectRatio;
            const auto hstep = right * tanf( pCamera->HorizontalFOV / hCount );

            // Temporary variables
            auto voffset = vstep * ((vCount / 2) - y_ind);

            if( (vCount & 1) == 0 )
            {
                // Adjust start offset when number of vertical rays is even
                voffset += vstep * 0.5f;
            }

            auto hoffset_start = hstep * (hCount / 2);

            if( (hCount & 1) == 0 )
            {
                // Adjust start offset when number of horizontal rays is even
                hoffset_start += hstep * 0.5f;
            }

            auto hoffset = hoffset_start - (hstep * x_ind);

            RayData threadRays[NumRaysPerThread];

            for( int ind = 0; ind < numRaysToSpawn; ++ind )
            {
                // Check if we need to advance to the next row
                if( x_ind == hCount )
                {
                    voffset -= vstep;
                    hoffset = hoffset_start;
                    y_ind++;
                }

                auto ray_d = voffset + hoffset + cameraDirection;
                ray_d.Normalize3();

                RayData ray;
                ray.Direction = ray_d;
                ray.Origin = cameraOrigin;

                // Store ray in the local array
                threadRays[ind] = ray;

                hoffset -= hstep;
                x_ind++;
            }

            // Copy to global memory
            memcpy( pRays + r_ind, threadRays, sizeof( RayData ) * numRaysToSpawn );
        }

        Camera::Camera( const Array<CameraData>& array, int index )
            : DataWrapper( array, index )
        {
        }

        Array<Camera::RayType::DataType> Camera::SpawnPrimaryRays( int hCount, int vCount )
        {
            Array<RayType::DataType> rays( hCount * vCount );

            DispatchParameters dispatchParams( (hCount * vCount + (NumRaysPerThread - 1)) / NumRaysPerThread );

            // Execute spawning kernel
            SpawnPrimaryRaysKernel<<<dispatchParams.NumBlocksPerGrid, dispatchParams.NumThreadsPerBlock>>>
                ( DeviceMemory.Data(), hCount, vCount, rays.Data() );

            return rays;
        }
    }
}
