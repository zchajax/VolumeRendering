Shader "Hidden/Cloud"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertDefault
            #pragma fragment Frag
            #include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"

            TEXTURE2D_SAMPLER2D(_MainTex, sampler_MainTex);
            TEXTURE2D_SAMPLER2D(_CameraDepthTexture, sampler_CameraDepthTexture);

            sampler3D _shapeNoise;
            sampler3D _detailNoise;
            sampler2D _weatherMap;
            sampler2D _maskNoise;
            sampler2D _blueNoise;

            float _shapeTiling;
            float _detailTiling;
            float _AbsorptionFromLight;
            float _AbsorptionFromCloud;
            float _jitterStrength;
            float _detailWeights;
            float _detailNoiseWeight;
            float _cloundDensity;
            float _step;
            float _shapeNoiseSpeed;
            float _detailNoiseSpeed;
            float _windDirection;

            float4x4 _InvProjMatrix;
            float4x4 _InvViewMatrix;
            float3 _boundsMin;
            float3 _boundsMax;
            float3 _WorldSpaceLightPos0;
            float4 _LightColor0;

            float2x2 Rot(float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            float4 GetWolrdPostionFromDepth(float2 uv, float depth)
            {
                float4 viewPos = mul(_InvProjMatrix, float4(2.0f * uv - 1.0, depth, 1.0));
                viewPos.xyz /= viewPos.w;
                return mul(_InvViewMatrix, float4(viewPos.xyz, 1.0));
            }

            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir)
            {
                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }


            float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
            {
                return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
            }

            float SampleDensity(float3 rayPos)
            {
                float3 center = (_boundsMax + _boundsMin) * 0.5;
                float3 size = _boundsMax - _boundsMin;
                float2 uv = (size.xz * 0.5 + (rayPos.xz - center.xz)) / max(size.x, size.z);

                float speedShape = _Time.y * _shapeNoiseSpeed;
                float speedDetail = _Time.y * _detailNoiseSpeed;

                float2 direction = float2(1.0, 1.0f);
               direction = mul(Rot(_windDirection), direction);

                float3 uvwShape = rayPos * _shapeTiling + float3(direction.x * speedShape, speedShape * 0.2, direction.y * speedShape);
                float3 uvwDetail = rayPos * _detailTiling + float3(direction.x * speedDetail, speedDetail * 0.2, direction.y * speedDetail);

                float4 maskNoise = tex2D(_maskNoise, uv + float2(speedShape * 0.5, 0));
                float4 weatherMap = tex2D(_weatherMap, uv);
                
                // Basic shape
                float4 shapeNoise = tex3D(_shapeNoise, uvwShape + (maskNoise.r * 0.1));

                // Detail shape
                float4 detailNoise = tex3D(_detailNoise, uvwDetail + (shapeNoise.r * 10 * 0.1));

                // edge falloff
                const float containerEdgeFadeDst = 10;
                float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - _boundsMin.x, _boundsMax.x - rayPos.x));
                float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - _boundsMin.z, _boundsMax.z - rayPos.z));
                float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

                float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.5);
                float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
                float height01 = (rayPos.y - _boundsMin.y) / size.y;
                float heightGradient = saturate(remap(height01, 0.0, gMin, 0, 1)) * saturate(remap(height01, 1, gMax, 0, 1));
                //heightGradient *= edgeWeight;

                float4 _shapeNoiseWeights = float4(-2.06, 27, -3.65, -0.08);
                float4 normalizedShapeWeights = _shapeNoiseWeights / dot(_shapeNoiseWeights, 1);
                float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
                float baseShapeDensity = shapeFBM;

                if (baseShapeDensity > 0)
                {
                    float detailFBM = pow(detailNoise.r, _detailWeights);
                    float oneMinusShape = 1 - baseShapeDensity;
                    float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
                    float cloudDensity = baseShapeDensity - detailFBM * detailErodeWeight * _detailNoiseWeight;

                    return saturate(cloudDensity * _cloundDensity);
                }

                return 0;

            }

            float lightmarch(float3 position)
            {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                float dstInsideBox = rayBoxDst(_boundsMin, _boundsMax, position, dirToLight).y;

                int numStepsLight = 8;
                float stepSize = dstInsideBox / numStepsLight;
                float totalDensity = 0;

                for (int step = 0; step < numStepsLight; step++) 
                {
                    position += dirToLight * stepSize;
                    totalDensity += max(0, SampleDensity(position) * stepSize);
                }

                float transmittance = exp(-totalDensity * _AbsorptionFromLight);
                return transmittance;
            }

            float hg(float a, float g) 
            {
                float g2 = g * g;
                return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
            }

            float phase(float a) 
            {
                float4 phaseParams = float4(.63, 1.0, 0.5, 1.58);

                float blend = .5;
                float hgBlend = hg(a, phaseParams.x) * (1 - blend) + hg(a, -phaseParams.y) * blend;
                return phaseParams.z + hgBlend * phaseParams.w;
            }

            float4 Frag(VaryingsDefault i) : SV_Target
            {
                float4 backgroundCol = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.texcoord);
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.texcoordStereo);
                float4 worldPos = GetWolrdPostionFromDepth(i.texcoord, depth);
                
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);

                float2 rayBoxInfo = rayBoxDst(_boundsMin, _boundsMax, rayOrigin, rayDir);
                float dstToBox = rayBoxInfo.x;
                float dstInsideBox = rayBoxInfo.y;

                float linearDepth = length(worldPos.xyz - _WorldSpaceCameraPos);
                float dstLimit = min(linearDepth - dstToBox, dstInsideBox);

                float3 entryPoint = rayOrigin + rayDir * dstToBox;

                float cosAngle = dot(rayDir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(cosAngle);

                // jitter
                float jitter = tex2D(_blueNoise, i.texcoord);

                float dstTravelled = 0.0;
                dstTravelled += jitter * _jitterStrength;

                float totalDensity = 0.0;
                float transmittance = 1.0;
                float lightEnergy = 0.0;

                int NumSteps = 64;
                float stepSize = _step;

                [unroll(NumSteps)]
                for (int i = 0; i < NumSteps; i++)
                {
                    if (dstTravelled < dstLimit)
                    {
                        float3 rayPos = entryPoint + (rayDir * dstTravelled * stepSize);
                        float density = SampleDensity(rayPos);

                        if (density > 0)
                        {
                            float lightTransmittance = lightmarch(rayPos);
                            lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                            transmittance *= exp(-density * stepSize * _AbsorptionFromCloud);

                            if (transmittance < 0.01)
                            {
                                break;
                            }
                        }
                    }
                    dstTravelled += stepSize;
                }
                
                float3 cloudCol = lightEnergy;
                float3 col = backgroundCol * transmittance + cloudCol;
                return float4(col, 0);
            }
            ENDHLSL
        }
    }
}
