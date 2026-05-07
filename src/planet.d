module planet;

import dagon;

class PlanetShader: Shader
{
   protected:
    String vs, fs;

    ShaderParameter!Matrix4x4f modelViewMatrix;
    ShaderParameter!Matrix4x4f projectionMatrix;
    ShaderParameter!Matrix4x4f viewMatrix;
    ShaderParameter!Matrix4x4f invViewMatrix;
    ShaderParameter!Matrix4x4f prevModelViewMatrix;

   public:
    this(Owner owner)
    {
        vs = Shader.load("shaders/Planet/Planet.vert.glsl");
        fs = Shader.load("shaders/Planet/Planet.frag.glsl");

        auto myProgram = New!ShaderProgram(vs, fs, this);
        super(myProgram, owner);
        
        modelViewMatrix = createParameter!Matrix4x4f("modelViewMatrix");
        projectionMatrix = createParameter!Matrix4x4f("projectionMatrix");
        viewMatrix = createParameter!Matrix4x4f("viewMatrix");
        invViewMatrix = createParameter!Matrix4x4f("invViewMatrix");
        prevModelViewMatrix = createParameter!Matrix4x4f("prevModelViewMatrix");
    }

    ~this()
    {
        vs.free();
        fs.free();
    }

    override void bindParameters(GraphicsState* state)
    {
        Material mat = state.material;
        
        // Matrices
        modelViewMatrix = &state.modelViewMatrix;
        projectionMatrix = &state.projectionMatrix;
        viewMatrix = &state.viewMatrix;
        invViewMatrix = &state.invViewMatrix;
        prevModelViewMatrix = &state.prevModelViewMatrix;
        
        // Diffuse
        glActiveTexture(GL_TEXTURE0);
        setParameter("diffuseTexture", cast(int)0);
        setParameter("diffuseVector", mat.baseColorFactor);
        if (mat.baseColorTexture)
        {
            mat.baseColorTexture.bind();
            setParameterSubroutine("diffuse", ShaderType.Fragment, "diffuseColorTexture");
        }
        else
        {
            glBindTexture(GL_TEXTURE_2D, 0);
            setParameterSubroutine("diffuse", ShaderType.Fragment, "diffuseColorValue");
        }
        
        super.bindParameters(state);
    }

    override void unbindParameters(GraphicsState* state)
    {
        super.unbindParameters(state);
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);
    }
}
