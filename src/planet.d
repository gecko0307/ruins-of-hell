module planet;

import dagon;

class PlanetShader: Shader
{
    String vs, fs;

    this(Owner owner)
    {
        vs = Shader.load("shaders/Planet/Planet.vert.glsl");
        fs = Shader.load("shaders/Planet/Planet.frag.glsl");

        auto myProgram = New!ShaderProgram(vs, fs, this);
        super(myProgram, owner);
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
        setParameter("modelViewMatrix", state.modelViewMatrix);
        setParameter("projectionMatrix", state.projectionMatrix);
        setParameter("viewMatrix", state.viewMatrix);
        setParameter("invViewMatrix", state.invViewMatrix);
        setParameter("prevModelViewMatrix", state.prevModelViewMatrix);
        
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
