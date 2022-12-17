//
//  CustomShader.metal
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/15.
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

[[visible]]
void pictureGeometryModifier(realitykit::geometry_parameters params)
{
    float3 pos = params.geometry().model_position();

    float windowX = (pos.x >= 0) ? windowX = pos.x / -0.5 + 1 : windowX = (pos.x + 0.5) / 0.5;
    float windowZ = (pos.z >= 0) ? windowZ = pos.z / -0.5 + 1 : windowZ = (pos.z + 0.5) / 0.5;

    // x axis: wave length = 0.2 [m], cycle = 8.0 [sec]
    // z axis: wave length = 0.3 [m], cycle = 10.0 [sec]
    // wave height = +/- 0.2 + 0.2 [m]
    float offsetY = windowX * windowZ *
        (cos( 3.14 * 2.0 * pos.x / 0.2 + 3.14 * 2.0 * params.uniforms().time() / 8.0 )
        * cos( 3.14 * 2.0 * pos.z / 0.3 + 3.14 * 2.0 * params.uniforms().time() / 10.0 ) * 0.2 + 0.2);

    params.geometry().set_model_position_offset(float3(0.0, offsetY, 0.0));
}
