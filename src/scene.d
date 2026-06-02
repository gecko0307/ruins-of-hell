module scene;

import std.math;
import std.random;
import dagon;
import dagon.ext.jolt;
import dagon.ext.audio;
import game;
import planet;
import steering;
import demon;

Vector2f lissajousCurve(float t)
{
    return Vector2f(sin(t), cos(2 * t));
}

Vector2f lemniscate(float t, float c = 1.0f)
{
    enum s2 = sqrt(2.0f);
    float a = c * s2 * cos(t);
    float sint = sin(t);
    float b = 1.0f / (1.0f + sint * sint);
    float x = a * b;
    float y = (a * sin(t)) * b;
    return Vector2f(x, y);
}

bool vectorIsNaN(Vector3f v)
{
    return v.x.isNaN || v.y.isNaN || v.z.isNaN;
}

bool quaternionIsNaN(Quaternionf q)
{
    return q.x.isNaN || q.y.isNaN || q.z.isNaN || q.w.isNaN;
}

float easeOutElastic(float x)
{
    float c4 = (2 * PI) / 3;
    return x == 0? 0 : x == 1 ? 1 : pow(2, -10 * x) * sin((x * 10 - 0.75) * c4) + 1;
}

class GameScene: Scene
{
    LoadingScreen loadingScreen;
    
    MyGame game;
    JoltPhysicsWorld physicsWorld;
    
    AudioManager audio;
    WavStream music;
    WavStream ambient;
    Wav[2] footsteps;
    Wav fire;
    Wav shot;
    Wav reload;
    
    float musicStartTimer = 0.0f;
    bool musicStarted = false;
    
    TextureAsset aEnvmap;
    
    GLTFAsset aLevel;
    
    GLTFAsset aDemon;
    Demon demon;
    
    GLTFAsset aWeapon;
    
    TextureAsset aTexFireDiffuse;
    TextureAsset aTexSmokeDiffuse;
    TextureAsset aTexSpark;
    TextureAsset aTexBlood;
    TextureAsset aMoon;
    
    Entity eCharacter;
    JoltCharacterController character;
    FirstPersonViewComponent fpview;
    Entity cameraPivot;
    Camera camera;
    Vector2f camSwayVector = Vector2f(0.0f, 0.0f);
    float camSwayTime = 0.0f;
    float camSwayAmplitude = 0.05f;
    bool crouchPressed = false;
    
    Vector3f prevPosition;
    
    Entity eMuzzleFlash;
    TextureAsset aTexMuzzleFlash;
    Billboard muzzleFlashSprite;
    Light muzzleFlashLight;
    
    float gunSwayTime = 0.0f;
    float gunSwayAmplitude = 0.0666f;
    
    float footstepTimer = 0.0f;
    uint footstepIndex = 0;
    
    float playerAimingFactor = 0.0f;
    float playerShootingFactor = 0.0f;
    
    bool playerAiming = false;
    bool playerShooted = false;
    bool playerReloading = false;
    float playerReloadTime = 1.0f;
    bool canShoot = true;
    bool reloaded = false;
    
    int weaponReloadDirection = 0;
    float weaponReload = 0.0f;
    
    GLTFBlendedPose pose;
    Vector3f weaponPositionNormal = Vector3f(-0.02f, -0.16f, 0.13f);
    Vector3f weaponPositionAiming = Vector3f(-0.158f, -0.19f, 0.15f);
    Vector3f weaponPositionShootingOffset = Vector3f(0.0f, 0.0f, 0.03f);
    
    // -0.138, -0.03, 0.02
    Vector3f muzzleFlashPosition = Vector3f(-0.16f, 0.10f, 1.0f);
    
    ParticleSystem particleSystem;
    Material mParticlesBlood;
    
    Entity eCrosshair;
    TextureAsset aCrosshair;
    
    Entity eParticlesDebris;
    Emitter emitterDebris;
    float shootDebrisTimer = 0.0f;
    
    Entity eAltarVortex;
    
    UIWidget pauseBackground;
    
    this(MyGame game)
    {
        super(game);
        this.game = game;
        
        physicsWorld = New!JoltPhysicsWorld(eventManager, this);
        audio = game.audioManager;
        
        auto splashTextureAsset = addTextureAsset("assets/ui/loading.jpg", true);
        
        loadingScreen = New!LoadingScreen(game, this);
        loadingScreen.backgroundTexture = splashTextureAsset.texture;
        loadingScreen.progressbarCentered = false;
    }

    override void beforeLoad()
    {
        aEnvmap = addTextureAsset("assets/envmaps/ruins.hdr");
        
        aTexMuzzleFlash = addTextureAsset("assets/textures/muzzle_flash.png");
        aCrosshair = addTextureAsset("assets/textures/crosshair.png");
        aMoon = addTextureAsset("assets/textures/moon.png");
        aTexFireDiffuse = addTextureAsset("assets/textures/fire.png");
        aTexSmokeDiffuse = addTextureAsset("assets/textures/smoke.png");
        aTexSpark = addTextureAsset("assets/textures/spark.png");
        aTexBlood = addTextureAsset("assets/textures/blood.png");
        
        aLevel = addGLTFAsset("assets/ruins/ruins.gltf");
        
        aDemon = addGLTFAsset("assets/baal/baal.gltf");
        
        aWeapon = addGLTFAsset("assets/weapon/incinerator.gltf");
        
        music = audio.streamMusic("assets/music/ruins_of_hell.mp3");
        ambient = audio.streamMusic("assets/sounds/ambient.mp3");
        
        footsteps[0] = audio.loadSound("assets/sounds/footstep_ground1.wav");
        footsteps[1] = audio.loadSound("assets/sounds/footstep_ground2.wav");
        fire = audio.loadSound("assets/sounds/fire.wav");
        shot = audio.loadSound("assets/sounds/shot.wav");
        reload = audio.loadSound("assets/sounds/reload.wav");
    }
    
    override void onLoad(Time t, float progress)
    {
        loadingScreen.progressbar.position = Vector3f(
            (game.drawableWidth - loadingScreen.progressbarWidth) * 0.5f,
            game.drawableHeight - 40.0f, 0);
        loadingScreen.update(t, progress);
        loadingScreen.render();
    }

    override void afterLoad()
    {
        Texture cubemap = generateCubemap(1024, aEnvmap.texture, null);
        Texture prefilteredCubemap = prefilterCubemap(1024, cubemap, assetManager);
        Delete(cubemap);
        
        environment.backgroundColor = Color4f(0.0f, 0.0f, 0.1f, 1.0f);
        environment.ambientColor = Color4f(0.4f, 0.3f, 0.3f, 1.0f);
        environment.ambientMap = prefilteredCubemap;
        environment.ambientBRDF = game.deferredRenderer.brdf;
        environment.ambientEnergy = 1.0f;
        environment.fogColor = Color4f(0.4f, 0.35f, 0.35f, 1.0f);
        environment.fogStart = 0.0f;
        environment.fogEnd = 60.0f;
        
        auto moon = addLight(LightType.Sun);
        moon.color = Color4f(0.2f, 0.7f, 1.0f, 1.0f);
        moon.shadowEnabled = true;
        moon.energy = 10.0f;
        moon.turn(80.0f);
        moon.pitch(-30.0f);
        moon.angularRadius = 0.1f;
        moon.scatteringEnabled = true;
        moon.scattering = 0.2f;
        moon.mediumDensity = 0.025f;
        moon.scatteringUseShadow = true;
        moon.scatteringMaxRandomStepOffset = 0.05f;
        environment.sun = moon;
        
        auto eParticleSystem = addEntity();
        particleSystem = New!ParticleSystem(eventManager, eParticleSystem);
        
        auto eLevel = aLevel.rootEntity;
        useEntity(eLevel, true);
        
        JoltMeshShape levelShape = New!JoltMeshShape(aLevel, this);
        auto levelBody = physicsWorld.addStaticBody(eLevel, levelShape);
        levelBody.friction = 0.5f;
        
        // Character
        float characterHeight = 1.8f;
        float characterRadius = 0.6f;
        float characterMass = 80.0f;
        eCharacter = addEntity();
        eCharacter.position = Vector3f(-14.9f, 0.0f, 11.0f);
        character = New!JoltCharacterController(eventManager, physicsWorld, eCharacter, characterHeight, characterRadius, characterMass);
        character.normalEyeHeight = characterHeight - 0.15f;
        character.crouchEyeHeight = characterHeight * 0.5f;
        character.headMargin = -0.2f;
        prevPosition = eCharacter.position;
        
        cameraPivot = addEntity(eCharacter);
        cameraPivot.position.y = character.eyeHeight;
        fpview = New!FirstPersonViewComponent(eventManager, cameraPivot);
        fpview.active = true;
        fpview.turn = -45.0f;
        camera = addCamera(cameraPivot);
        camera.fov = 45.0f;
        game.renderer.activeCamera = camera;
        audio.listener = camera;
        
        useEntity(aWeapon.rootEntity, true);
        aWeapon.rootEntity.setParent(camera);
        aWeapon.rootEntity.position = weaponPositionNormal;
        foreach(node; aWeapon.nodes)
        {
            node.entity.blurMask = 0.0f;
            node.entity.castShadow = false;
        }
        
        eMuzzleFlash = addEntity(aWeapon.rootEntity);
        muzzleFlashSprite = New!Billboard(assetManager);
        eMuzzleFlash.drawable = muzzleFlashSprite;
        eMuzzleFlash.material = addMaterial();
        eMuzzleFlash.material.baseColorTexture = aTexMuzzleFlash.texture;
        eMuzzleFlash.material.emissionTexture = aTexMuzzleFlash.texture;
        eMuzzleFlash.material.emissionFactor = Color4f(1.0f, 1.0f, 1.0f, 1.0f);
        eMuzzleFlash.material.emissionEnergy = 3.0f;
        eMuzzleFlash.material.shadeless = true;
        eMuzzleFlash.material.blendMode = Additive;
        eMuzzleFlash.material.depthWrite = false;
        eMuzzleFlash.transparent = true;
        eMuzzleFlash.blurMask = 0.0f;
        eMuzzleFlash.castShadow = false;
        eMuzzleFlash.position = muzzleFlashPosition;
        eMuzzleFlash.scaling = Vector3f(0.3f, 0.3f, 0.3f);
        eMuzzleFlash.opacity = 0.0;
        muzzleFlashSprite.rotation = 90.0f;
        
        muzzleFlashLight = super.addLight(LightType.AreaSphere, eMuzzleFlash);
        muzzleFlashLight.castShadow = false;
        muzzleFlashLight.color = Color4f(1.0f, 0.6f, 0.2f, 1.0f);
        muzzleFlashLight.energy = 50.0f;
        muzzleFlashLight.radius = 0.2f;
        muzzleFlashLight.volumeRadius = 15.0f;
        
        auto nArm = aWeapon.node("arm");
        pose = New!GLTFBlendedPose(nArm.skin, assetManager);
        pose.switchToAnimation(aWeapon.animation("arm_rootAction"));
        auto eArm = nArm.entity;
        eArm.pose = pose;
        
        auto eSky = addEntity();
        auto psync = New!PositionSync(eventManager, eSky, camera);
        eSky.drawable = New!ShapeBox(Vector3f(1.0f, 1.0f, 1.0f), assetManager);
        eSky.scaling = Vector3f(100.0f, 100.0f, 100.0f);
        eSky.layer = EntityLayer.Background;
        eSky.material = New!Material(assetManager);
        eSky.material.depthWrite = false;
        eSky.material.useCulling = false;
        auto skyShader = New!StarfieldSkyShader(assetManager);
        skyShader.spaceColorZenith = Color4f(0.35f, 0.3f, 0.3f, 1.0f);
        skyShader.spaceColorHorizon = Color4f(0.6f, 0.4f, 0.3f, 1.0f);
        skyShader.starsBrightness = 20.0f;
        skyShader.sunEnergy = 0.0f;
        eSky.material.shader = skyShader;
        eSky.gbufferMask = 0.0f;
        
        auto light = addAreaLight(LightType.AreaSphere, Vector3f(0.0f, 1.0f, 0.0f), Color4f(1.0f, 0.4f, 0.1f), 40.0f, 0.5f, 30.0f);
        light.shadowEnabled = true;
        
        auto eMoon = addEntity();
        auto moonPsync = New!PositionSync(eventManager, eMoon, camera);
        eMoon.layer = EntityLayer.Background;
        eMoon.drawable = New!ShapePlane(10.0f, 10.0f, 1, assetManager);
        eMoon.material = addMaterial();
        eMoon.material.baseColorTexture = aMoon.texture;
        eMoon.material.depthWrite = false;
        eMoon.material.useCulling = false;
        eMoon.material.blendMode = Transparent;
        auto planetShader = New!PlanetShader(assetManager);
        eMoon.material.shader = planetShader;
        eMoon.position = moon.rotation.rotate(Vector3f(0.0f, 0.0f, 1.0f)) * 25.0f;
        Vector3f moonDirection = -eMoon.position.normalized;
        eMoon.rotation = 
            rotationBetween(Vector3f(0.0f, 1.0f, 0.0f), moonDirection) *
            rotationQuaternion!float(Axis.y, degtorad(180.0f));
        
        game.deferred.passLight.volumetricScatteringEnabled = false;
        
        auto mParticlesSmoke = addMaterial();
        mParticlesSmoke.baseColorTexture = aTexSmokeDiffuse.texture;
        mParticlesSmoke.sphericalNormal = true;
        mParticlesSmoke.shadeless = true;
        mParticlesSmoke.blendMode = Transparent;
        mParticlesSmoke.depthWrite = false;
        mParticlesSmoke.emissionEnergy = 2.0f;
        mParticlesSmoke.sun = moon;
        
        auto mParticlesFire = addMaterial();
        mParticlesFire.baseColorTexture = aTexFireDiffuse.texture;
        mParticlesFire.sphericalNormal = true;
        mParticlesFire.shadeless = true;
        mParticlesFire.blendMode = Additive;
        mParticlesFire.depthWrite = false;
        mParticlesFire.emissionEnergy = 5.0f;
        mParticlesFire.sun = moon;
        
        auto mParticlesSpark = addMaterial();
        mParticlesSpark.baseColorTexture = aTexSpark.texture;
        mParticlesSpark.sphericalNormal = true;
        mParticlesSpark.shadeless = true;
        mParticlesSpark.blendMode = Additive;
        mParticlesSpark.depthWrite = false;
        mParticlesSpark.emissionEnergy = 40.0f;
        mParticlesSpark.sun = moon;
        
        auto mParticlesDebris = addMaterial();
        mParticlesDebris.baseColorTexture = aTexSpark.texture;
        mParticlesDebris.sphericalNormal = true;
        mParticlesDebris.shadeless = true;
        mParticlesDebris.blendMode = Additive;
        mParticlesDebris.depthWrite = false;
        mParticlesDebris.emissionEnergy = 70.0f;
        mParticlesDebris.sun = moon;
        
        mParticlesBlood = addMaterial();
        mParticlesBlood.baseColorTexture = aTexBlood.texture;
        mParticlesBlood.sphericalNormal = true;
        mParticlesBlood.shadeless = false;
        mParticlesBlood.blendMode = Transparent;
        mParticlesBlood.depthWrite = false;
        mParticlesBlood.emissionEnergy = 2.0f;
        mParticlesBlood.sun = moon;
        
        auto eParticlesSmoke = addEntity();
        auto emitterSmoke = New!Emitter(eParticlesSmoke, particleSystem, 50);
        emitterSmoke.material = mParticlesSmoke;
        emitterSmoke.startColor = Color4f(0.5f, 0.65f, 0.8f, 0.2f);
        emitterSmoke.endColor = Color4f(0.5f, 0.65f, 0.8f, 0.0f);
        emitterSmoke.initialDirectionRandomFactor = 0.2f;
        emitterSmoke.scaleStep = Vector2f(1.0f, 1.0f);
        emitterSmoke.rotationStep = 0.0f;
        emitterSmoke.minInitialSpeed = 5.0f;
        emitterSmoke.maxInitialSpeed = 10.0f;
        emitterSmoke.minSize = 0.5f;
        emitterSmoke.maxSize = 2.0f;
        emitterSmoke.reset();
        eParticlesSmoke.position = Vector3f(-1.0f, 2.0f, 0.3f);
        eParticlesSmoke.visible = true;
        
        auto eParticlesMist = addEntity();
        auto emitterMist = New!Emitter(eParticlesMist, particleSystem, 150);
        emitterMist.material = mParticlesSmoke;
        emitterMist.startColor = Color4f(0.5f, 0.65f, 0.8f, 1.0f);
        emitterMist.endColor = Color4f(0.5f, 0.65f, 0.8f, 0.0f);
        emitterMist.initialDirectionRandomFactor = 0.3f;
        emitterMist.initialPositionRandomRadii = Vector3f(25.0f, 0.0f, 25.0f);
        emitterMist.scaleStep = Vector2f(1.0f, 1.0f);
        emitterMist.rotationStep = 0.1f;
        emitterMist.minInitialSpeed = 0.5f;
        emitterMist.maxInitialSpeed = 1.0f;
        emitterMist.minSize = 2.0f;
        emitterMist.maxSize = 4.0f;
        emitterMist.fadeInDuration = 0.5f;
        emitterMist.minLifetime = 3.0f;
        emitterMist.maxLifetime = 5.0f;
        emitterMist.reset();
        eParticlesMist.position = Vector3f(0.0f, -1.0f, 0.0f);
        eParticlesMist.visible = true;
        
        auto eParticlesFire = addEntity();
        auto emitterFire = New!Emitter(eParticlesFire, particleSystem, 50);
        emitterFire.material = mParticlesFire;
        emitterFire.startColor = Color4f(1.0f, 0.8f, 0.5f, 1.0f);
        emitterFire.endColor = Color4f(0.5f, 0.0f, 0.0f, 0.0f);
        emitterFire.initialDirectionRandomFactor = 0.0f;
        emitterFire.scaleStep = Vector2f(-2.2f, -2.0f);
        emitterFire.rotationStep = 0.1f;
        emitterFire.minInitialSpeed = 3.0f;
        emitterFire.maxInitialSpeed = 7.0f;
        emitterFire.minSize = 1.5f;
        emitterFire.maxSize = 1.5f;
        emitterFire.minLifetime = 0.5f;
        emitterFire.maxLifetime = 1.0f;
        emitterFire.reset();
        eParticlesFire.position = Vector3f(-0.8f, 0.5f, 0.3f);
        eParticlesFire.visible = true;
        
        eAltarVortex = addEntity();
        auto altarVortex = New!Vortex(eAltarVortex, particleSystem, 4.0f, 4.0f);
        
        auto eParticlesSparks = addEntity();
        auto emitterSparks = New!Emitter(eParticlesSparks, particleSystem, 200);
        emitterSparks.material = mParticlesSpark;
        emitterSparks.startColor = Color4f(1.0f, 0.0f, 0.0f, 1.0f);
        emitterSparks.endColor = Color4f(0.0f, 0.0f, 0.0f, 0.0f);
        emitterSparks.initialDirectionRandomFactor = 0.5f;
        emitterSparks.initialPositionRandomRadii = Vector3f(20.0f, 0.0f, 20.0f);
        emitterSparks.scaleStep = Vector2f(0.0f, 0.0f);
        emitterSparks.rotationStep = 0.0f;
        emitterSparks.minInitialSpeed = 2.0f;
        emitterSparks.maxInitialSpeed = 4.0f;
        emitterSparks.minSize = 0.02f;
        emitterSparks.maxSize = 0.02f;
        emitterSparks.fadeInDuration = 0.2f;
        emitterSparks.minLifetime = 1.0f;
        emitterSparks.maxLifetime = 3.0f;
        emitterSparks.reset();
        eParticlesSparks.position = Vector3f(0.0f, 0.5f, 0.0f);
        eParticlesSparks.visible = true;
        
        eParticlesDebris = addEntity();
        emitterDebris = New!Emitter(eParticlesDebris, particleSystem, 100);
        emitterDebris.material = mParticlesDebris;
        emitterDebris.startColor = Color4f(1.0f, 0.8f, 0.4f, 1.0f);
        emitterDebris.endColor = Color4f(1.0f, 0.0f, 0.0f, 0.0f);
        emitterDebris.initialDirectionRandomFactor = 0.6f;
        emitterDebris.initialPositionRandomRadii = Vector3f(0.0f, 0.0f, 0.0f);
        emitterDebris.scaleStep = Vector2f(0.1f, 0.0f);
        emitterDebris.rotationStep = 10.0f;
        emitterDebris.minInitialSpeed = 6.0f;
        emitterDebris.maxInitialSpeed = 10.0f;
        emitterDebris.minSize = 0.02f;
        emitterDebris.maxSize = 0.02f;
        emitterDebris.fadeInDuration = 0.01f;
        emitterDebris.minLifetime = 0.5f;
        emitterDebris.maxLifetime = 1.0f;
        emitterDebris.gravity = Vector3f(0.0f, -15.0f, 0.0f);
        emitterDebris.reset();
        emitterDebris.emitting = false;
        eParticlesDebris.visible = true;
        
        auto hudShader = New!HUDShader(assetManager);
        eCrosshair = addEntityHUD();
        eCrosshair.drawable = New!ShapeQuad(assetManager);
        eCrosshair.scaling = Vector3f(64.0f, 64.0f, 1.0f);
        eCrosshair.position = Vector3f(
            game.drawableWidth * 0.5f - 32.0f,
            game.drawableHeight * 0.5f - 32.0f,
            0.0f
        );
        eCrosshair.material = addMaterial();
        eCrosshair.material.shader = hudShader;
        eCrosshair.material.baseColorTexture = aCrosshair.texture;
        eCrosshair.material.depthWrite = false;
        eCrosshair.material.useCulling = false;
        eCrosshair.material.blendMode = Transparent;
        eCrosshair.material.opacity = 0.0f;
        
        pauseBackground = addWidget!UIWidget();
        pauseBackground.fitToParent = true;
        pauseBackground.backgroundUnfocusedColor = Color4f(0.0f, 0.0f, 0.0f, 0.5f);
        pauseBackground.backgroundFocusedColor = Color4f(0.0f, 0.0f, 0.0f, 0.5f);
        pauseBackground.background.visible = false;
        
        // Demon
        demon = New!Demon(this, aDemon, assetManager);
        
        //
        eventManager.showCursor(false);
        
        audio.playMusic(ambient, true);
        
        auto fireVoice = audio.playMusicAtPosition(fire, eParticlesFire.position, true);
        audio.setAttenuation(fireVoice, AttenuationModel.ExponentialDistance, 0.2f);
    }
    
    Light addAreaLight(LightType type, Vector3f pos, Color4f color, float energy, float areaRadius, float volumeRadius)
    {
        auto light = super.addLight(type);
        light.castShadow = false;
        light.position = pos;
        light.color = color;
        light.energy = energy;
        light.radius = areaRadius;
        light.volumeRadius = volumeRadius;
        light.scatteringEnabled = false;
        light.mediumDensity = 0.01f;
        return light;
    }
    
    override void onMouseButtonDown(int button)
    {
        if (!paused)
        {
            if (button == MB_LEFT && canShoot)
            {
                audio.play(shot);
                canShoot = false;
                playerShooted = true;
                reloaded = false;
                playerReloadTime = 0.0f;
                muzzleFlashSprite.rotation = uniform(0.0f, 1.0f) * 360.0f;
                eMuzzleFlash.opacity = 1.0f;
                shootRaycast = true;
            }
        }
    }
    
    bool shootRaycast = false;
    
    float playerSpeedFactor = 0.0f;
    
    override void onUpdate(Time t)
    {
        if (shootRaycast)
        {
            shootRaycast = false;
            Vector3f rayStart = eCharacter.position + cameraPivot.position + camera.position;
            Vector3f rayEnd = rayStart - fpview.direction * 100.0f;
            bool demonHit = false;
            bool sceneryHit = false;
            
            Vector3f demonHitPosition = rayEnd;
            float damageRatio = 0.0f;
            
            demonHit = demon.hitTest(rayStart, -fpview.direction, 100.0f, demonHitPosition, damageRatio);
            
            Vector3f sceneryHitPosition, sceneryHitNormal;
            JoltRigidBody hitBody;
            if (physicsWorld.raycast(rayStart, rayEnd, sceneryHitPosition, sceneryHitNormal, hitBody))
            {
                sceneryHit = true;
                if (demonHit)
                {
                    float sceneryHitDistance = (sceneryHitPosition - rayStart).lengthsqr;
                    float demonHitDistance = (demonHitPosition - rayStart).lengthsqr;
                    if (sceneryHitDistance < demonHitDistance)
                        demonHit = false;
                }
            }
            
            if (demonHit)
            {
                demon.hit(demonHitPosition, damageRatio);
            }
            else if (sceneryHit)
            {
                eParticlesDebris.position = sceneryHitPosition;
                emitterDebris.initialDirection = sceneryHitNormal;
                emitterDebris.emitting = true;
                shootDebrisTimer = 1.0f;
                eParticlesDebris.update(t);
            }
        }
        
        if (!musicStarted)
        {
            musicStartTimer += t.delta;
            if (musicStartTimer > 10.0f)
            {
                audio.playMusic(music, true);
                musicStarted = true;
            }
        }
        
        demon.update(t);
        
        if (fpview.active)
        {
            if (eventManager.mouseButtonPressed[MB_RIGHT])
                playerAiming = true;
            else
                playerAiming = false;
        }
        
        bool playerRunning = false;
        bool playerWalking = false;
        float camSway = 0.0f;
        float gunSway = 0.0f;
        
        bool isCrouching = character.isCrouching;
        
        float speed = 4.0f;
        const float jumpSpeed = 7.0f;
        if (isCrouching || playerAiming)
        {
            speed = 2.0f;
        }
        else if (fpview.active && eventManager.keyPressed[KEY_LSHIFT])
        {
            speed = 7.0f;
            playerRunning = true;
        }
        
        Vector3f forward = -fpview.directionHorizontal;
        Vector3f right = fpview.right;
        
        bool onGround = character.onGround;
        
        float playerSpeed = distance(eCharacter.position, prevPosition) / t.delta;
        prevPosition = eCharacter.position;
        
        if (fpview.active)
        {
            if (eventManager.keyPressed[KEY_W])
            {
                if (playerRunning && playerSpeed > 0.5f)
                    playerSpeedFactor += t.delta;
                else
                    playerSpeedFactor -= 8.0f * t.delta;
                character.move( forward * speed);
                playerWalking = onGround;
            }
            else if (eventManager.keyPressed[KEY_S])
            {
                if (playerRunning && playerSpeed > 0.5f)
                    playerSpeedFactor += t.delta;
                else
                    playerSpeedFactor -= 8.0f * t.delta;
                character.move(-forward * speed);
                playerWalking = onGround;
            }
            else playerSpeedFactor -= 8.0f * t.delta;
            
            if (eventManager.keyPressed[KEY_A]) { character.move(-right * speed); playerWalking = onGround; }
            if (eventManager.keyPressed[KEY_D]) { character.move( right * speed); playerWalking = onGround; }
            if (eventManager.keyPressed[KEY_SPACE]) { character.jump(jumpSpeed); character.crouch(false); }
            if (eventManager.keyPressed[KEY_C])
            {
                if (!crouchPressed)
                {
                    character.crouch(!isCrouching);
                    crouchPressed = true;
                }
            }
            else crouchPressed = false;
        }
        
        playerSpeedFactor = clamp(playerSpeedFactor, 0.0f, 1.0f);
        
        physicsWorld.update(t);
        
        cameraPivot.position.y = character.eyeHeight;
        
        if (playerAiming)
        {
            if (playerWalking)
                camSway = 3.0f * t.delta;
            else
                camSway = 0.2f * t.delta;
            gunSway = 0.0f;
        }
        else if (playerWalking)
        {
            if (isCrouching)
            {
                camSway = 5.0f * t.delta;
                gunSway = 4.0f * t.delta;
            }
            else if (playerRunning)
            {
                camSway = 11.0f * t.delta;
                gunSway = 10.0f * t.delta;
            }
            else
            {
                camSway = 8.0f * t.delta;
                gunSway = 7.0f * t.delta;
            }
            
            if (playerRunning) footstepTimer += 2.0f * t.delta;
            else footstepTimer += t.delta;
            if (footstepTimer > 0.5f)
            {
                footstepTimer = 0.0;
                audio.play(footsteps[footstepIndex]);
                footstepIndex = footstepIndex? 0 : 1;
            }
        }
        else
        {
            camSway = 0.2f * t.delta;
            gunSway = 0.5f * t.delta;
        }
        
        camSwayTime += camSway;
        if (camSwayTime >= 2.0f * PI)
            camSwayTime = 0.0f;
        
        gunSwayTime += gunSway;
        if (gunSwayTime >= 2.0f * PI)
            gunSwayTime = 0.0f;
        
        float aimSpeed = 6.0f;
        if (playerAiming)
        {
            if (playerAimingFactor < 1.0f)
                playerAimingFactor += aimSpeed * t.delta;
            if (playerAimingFactor >= 1.0f)
                playerAimingFactor = 1.0f;
        }
        else
        {
            if (playerAimingFactor > 0.0f)
                playerAimingFactor -= aimSpeed * t.delta;
            if (playerAimingFactor <= 0.0f)
                playerAimingFactor = 0.0f;
        }
        
        if (playerShooted)
        {
            if (playerShootingFactor < 1.0f)
                playerShootingFactor += 15.0f * t.delta;
            else
            {
                playerShootingFactor = 1.0f;
                playerShooted = false;
                playerReloading = true;
            }
        }
        else if (playerReloading)
        {
            if (playerShootingFactor > 0.0f)
                playerShootingFactor -= 3.0f * t.delta;
            else
            {
                playerShootingFactor = 0.0f;
                
                if (playerReloadTime < 0.8f)
                    playerReloadTime += 1.2f * t.delta;
                else
                {
                    playerReloadTime = 0.8f;
                    canShoot = true;
                    playerReloading = false;
                    weaponReloadDirection = 0;
                }
                
                if (weaponReloadDirection == 0 && !reloaded)
                {
                    weaponReloadDirection = 1;
                }
                
                if (playerReloadTime > 0.25f && !reloaded && weaponReloadDirection == 1)
                {
                    audio.play(reload);
                    reloaded = true;
                }
                
                if (weaponReloadDirection == 1)
                {
                    if (weaponReload < 1.0f)
                        weaponReload += 3.0f * t.delta;
                    else
                    {
                        weaponReloadDirection = -1;
                        weaponReload = 1.0f;
                    }
                }
                else if (weaponReloadDirection == -1)
                {
                    if (weaponReload > 0.0f)
                        weaponReload -= 3.0f * t.delta;
                    else
                    {
                        weaponReloadDirection = 0;
                        weaponReload = 0.0f;
                    }
                }
            }
        }
        
        if (eMuzzleFlash.opacity > 0.0f)
            eMuzzleFlash.opacity -= 6.0f * t.delta;
        else
            eMuzzleFlash.opacity = 0.0f;
        eMuzzleFlash.scaling = lerp(Vector3f(0.4f, 0.4f, 0.4f), Vector3f(0.3f, 0.3f, 0.3f), eMuzzleFlash.opacity);
        muzzleFlashLight.energy = 10.0f * eMuzzleFlash.opacity;
        
        float weaponRecoil = lerp(0.0f, 1.0f, easeOutQuad(playerShootingFactor));
        
        float shakeDistanceFactor = 0.0f; //1.0f - clamp(distance(eDemon.position, eCharacter.position) / 20.0f, 0.0f, 1.0f);
        float shakeFactor = 0.0f; //(1.0f - easeOutElastic(1.0f - demonFootstepFactor)) * 0.1f * (shakeDistanceFactor * shakeDistanceFactor);
        
        float easedAimingFactor = easeInOutQuad(playerAimingFactor);
        
        Vector2f camSwayVector = lissajousCurve(camSwayTime) * camSwayAmplitude;
        camera.position = Vector3f(camSwayVector.x, camSwayVector.y + shakeFactor, weaponRecoil * 0.5f);
        camera.fov = lerp(55.0f, 40.0f, easedAimingFactor);
        fpview.roll = sin(camSwayTime) * 0.25f;
        
        Vector2f gunSwayVector = lissajousCurve(gunSwayTime) * gunSwayAmplitude;
        aWeapon.rootEntity.position = 
            lerp(weaponPositionNormal + Vector3f(gunSwayVector.x * 0.1f, gunSwayVector.y * 0.1f, 0.0f), weaponPositionAiming, easedAimingFactor) +
            weaponPositionShootingOffset * easeOutQuad(playerShootingFactor) + 
            Vector3f(0.0f,
                -fpview.pitch / 90.0f * 0.055f + shakeFactor * 0.01f - easeInOutBack(weaponReload) * 0.05f,
                weaponRecoil * 0.05f);
        aWeapon.rootEntity.rotation =
            rotationQuaternion!float(Axis.x, degtorad(fpview.pitch * 0.1f + weaponRecoil * 0.5f)) *
            rotationQuaternion!float(Axis.y, degtorad(180.0f)) *
            rotationQuaternion!float(Axis.z, degtorad(4.0f * easeInOutBack(weaponReload)));
        
        game.postProcessingRenderer.depthOfFieldEnabled = playerAiming || paused;
        game.postProcessingRenderer.lensDistortionDispersion = lerp(0.05f, 0.3f, easedAimingFactor);
        game.postProcessingRenderer.vignetteStrength = lerp(0.5f, 0.8f, easedAimingFactor);
        game.postProcessingRenderer.radialBlurAmount = lerp(0.0f, 0.02f, playerSpeedFactor);
        
        eCrosshair.material.opacity = lerp(0.0f, 0.75f, playerAimingFactor);
        
        pose.update(t);
        
        audio.update(t);
        
        eCrosshair.scaling = lerp(
            Vector3f(64.0f, 64.0f, 1.0f),
            Vector3f(64.0f * 1.1f, 64.0f * 1.1f, 1.0f),
            weaponRecoil
        );
        
        eCrosshair.position = Vector3f(
            game.drawableWidth * 0.5f - eCrosshair.scaling.x * 0.5f,
            game.drawableHeight * 0.5f - eCrosshair.scaling.y * 0.5f,
            0.0f
        );
        
        if (shootDebrisTimer > 0.0f)
            shootDebrisTimer -= 20.0f * t.delta;
        else
        {
            shootDebrisTimer = 0.0f;
            emitterDebris.emitting = false;
        }
    }
    
    override void onKeyDown(int key)
    {
        if (key == KEY_ESCAPE)
        {
            togglePause();
        }
        else if (key == KEY_F12)
        {
            application.takeScreenshot("screenshots/screenshot");
        }
        else if (key == KEY_F1)
        {
            logInfo("eCharacter.position: ", eCharacter.position);
        }
    }
    
    void togglePause()
    {
        if (!paused)
        {
            fpview.active = false;
            eventManager.showCursor(true);
            paused = true;
            
            pauseBackground.background.visible = true;
            
            game.postProcessingRenderer.depthOfFieldEnabled = true;
            game.postProcessingRenderer.dofManual = true;
            game.postProcessingRenderer.dofNearStart = 0.0;
            game.postProcessingRenderer.dofNearDistance = 0.0;
            game.postProcessingRenderer.dofFarStart = 0.0;
            game.postProcessingRenderer.dofFarDistance = 0.0;
        }
        else
        {
            fpview.active = true;
            eventManager.showCursor(false);
            paused = false;
            pauseBackground.background.visible = false;
            game.postProcessingRenderer.dofManual = false;
        }
    }
    
    override void onKeyUp(int key) { }
    override void onTextInput(dchar code) { }
    
    override void onMouseButtonUp(int button) { }
    override void onMouseWheel(int x, int y) { }
    override void onControllerButtonDown(uint deviceIndex, int btn) { }
    override void onControllerButtonUp(uint deviceIndex, int btn) { }
    override void onControllerAxisMotion(uint deviceIndex, int axis, float value) { }
    override void onResize(int width, int height) { }
    override void onFocusLoss() { }
    override void onFocusGain() { }
    override void onDropFile(string filename) { }
    override void onKeyboardLayoutChange() { }
    override void onUserEvent(int code, void* payload) { }
    override void onQuit() { }
}
