using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

[Serializable]
[PostProcess(typeof(CloudRenderer), PostProcessEvent.AfterStack, "Unity/Cloud")]
public class Cloud : PostProcessEffectSettings
{
    public TextureParameter shapNoiseMap = new TextureParameter { value = null };
    public TextureParameter detailNoiseMap = new TextureParameter { value = null };
    public TextureParameter weatherMap = new TextureParameter { value = null };
    public TextureParameter maskNoiseMap = new TextureParameter { value = null };
    public TextureParameter blueNoiseMap = new TextureParameter { value = null };

    public FloatParameter shapeTilling = new FloatParameter { value = 0.01f };
    public FloatParameter detailTilling = new FloatParameter { value = 0.1f };
    public FloatParameter AbsorptionFromLight = new FloatParameter { value = 1.0f };
    public FloatParameter AbsorptionFromCloud = new FloatParameter { value = 1.0f };
    public FloatParameter jitterStrength = new FloatParameter { value = 1.0f };

    public FloatParameter detailWeights = new FloatParameter { value = 1.0f };
    public FloatParameter detailNoiseWeights = new FloatParameter { value = 1.0f };
    public FloatParameter cloudDensity = new FloatParameter { value = 1.0f };
    public FloatParameter step = new FloatParameter { value = 1.0f };
    public FloatParameter shapeNoiseSpeed = new FloatParameter { value = 0.05f };
    public FloatParameter detailNoiseSpeed = new FloatParameter { value = 0.8f };
    public FloatParameter windDirection = new FloatParameter { value = 1.5f };
}

public class CloudRenderer : PostProcessEffectRenderer<Cloud>
{
    Transform cloudTransform;

    public override void Init()
    {
        var cloud =GameObject.Find("Cloud");

        if (cloud != null)
        {
            cloudTransform = cloud.GetComponent<Transform>();
        }
    }

    public override void Render(PostProcessRenderContext context)
    {
        if (cloudTransform == null)
        {
            return;
        }

        var sheet = context.propertySheets.Get(Shader.Find("Hidden/Cloud"));

        var projMatrix = GL.GetGPUProjectionMatrix(context.camera.projectionMatrix, false);
        sheet.properties.SetMatrix("_InvProjMatrix", projMatrix.inverse);
        sheet.properties.SetMatrix("_InvViewMatrix", context.camera.cameraToWorldMatrix);

        Vector3 boundsMin = cloudTransform.position - cloudTransform.localScale / 2;
        Vector3 boundsMax = cloudTransform.position + cloudTransform.localScale / 2;
        sheet.properties.SetVector("_boundsMin", boundsMin);
        sheet.properties.SetVector("_boundsMax", boundsMax);

        if (settings.shapNoiseMap.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_shapeNoise"), settings.shapNoiseMap.value);
        }

        if (settings.detailNoiseMap.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_detailNoise"), settings.detailNoiseMap.value);
        }

        if (settings.weatherMap.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_weatherMap"), settings.weatherMap.value);
        }

        if (settings.weatherMap.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_maskNoise"), settings.maskNoiseMap);
        }

        if (settings.blueNoiseMap.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_blueNoise"), settings.blueNoiseMap) ;
        }

        sheet.properties.SetFloat("_shapeTiling", settings.shapeTilling);
        sheet.properties.SetFloat("_detailTiling", settings.detailTilling);
        sheet.properties.SetFloat("_AbsorptionFromLight", settings.AbsorptionFromLight);
        sheet.properties.SetFloat("_AbsorptionFromCloud", settings.AbsorptionFromCloud);
        sheet.properties.SetFloat("_jitterStrength", settings.jitterStrength);
        sheet.properties.SetFloat("_detailWeights", settings.detailWeights);
        sheet.properties.SetFloat("_detailNoiseWeight", settings.detailNoiseWeights);
        sheet.properties.SetFloat("_cloundDensity", settings.cloudDensity);
        sheet.properties.SetFloat("_step", settings.step);
        sheet.properties.SetFloat("_shapeNoiseSpeed", settings.shapeNoiseSpeed);
        sheet.properties.SetFloat("_detailNoiseSpeed", settings.detailNoiseSpeed);
        sheet.properties.SetFloat("_windDirection", settings.windDirection);

        context.command.BlitFullscreenTriangle(context.source, context.destination, sheet, 0);
    }

    public override DepthTextureMode GetCameraFlags()
    {
        return DepthTextureMode.Depth;
    }
}
