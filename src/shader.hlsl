struct VS_INPUT {
    float2 position     : POSITION;
    float4 col          : COL;
    float2 uv           : UV;
    float4 col_override : COL_OVERRIDE;
    uint tex_index        : BYTES;
};

struct PS_INPUT {
    float4 position     : SV_POSITION;
    float4 col          : COL;
    float2 uv           : UV;
    float4 col_override : COL_OVERRIDE;
    uint tex_index        : BYTES;
};

Texture2D mainAtlas       : register(t0);
Texture2D fontAtlas       : register(t1);
SamplerState samplerState : register(s0);

PS_INPUT vs_main(VS_INPUT input) {
    PS_INPUT output;
    output.position     = float4(input.position, 0.0, 1.0);
    output.col          = input.col;
    output.uv           = input.uv;
    output.tex_index    = input.tex_index;
    output.col_override = input.col_override;
    return output;
}

float4 ps_main(PS_INPUT input) : SV_TARGET {
    float4 col_out = input.col;
    float4 tex_col = float4(1.0, 1.0, 1.0, 1.0);

    if (input.tex_index == 0) {
        tex_col = mainAtlas.Sample(samplerState, input.uv);
    } else if (input.tex_index == 1) {
        tex_col.a = fontAtlas.Sample(samplerState, input.uv).r;
    } else if (input.tex_index == 255) {
        return col_out;
    }

    col_out *= tex_col;

    col_out.rgb = lerp(col_out.rgb, input.col_override.rgb, input.col_override.a);

    return col_out;
}

