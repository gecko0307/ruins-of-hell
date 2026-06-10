module demon;

import std.math;
import std.random;

import dagon;
import dagon.ext.jolt;
import dagon.ext.audio;

import scene;

struct CharacterHitbox
{
    Entity entity;
    Vector3f halfExtents;
    float damageRatio;
}

enum DemonState: uint
{
    Idle = 0,
    Walk = 1,
    Defeated = 2,
    Damage = 3,
    Taunt = 4,
    Attack = 5
}

class Demon: EventListener
{
    GameScene scene;
    
    Wav[2] sfxFootsteps;
    Wav[3] sfxGrowl;
    Wav sfxTauntGrowl;
    Wav sfxDamageGrowl;
    Wav sfxDyingGrowl;
    
    GLTFAsset asset;
    GLTFBlendedPose pose;
    GLTFAnimation animSwipe;
    GLTFAnimation animTaunt;
    GLTFAnimation animDying;
    GLTFAnimation animHit;
    GLTFAnimation animPunch;
    GLTFAnimation animWalk1;
    
    Entity entity;
    Material material;
    
    CharacterHitbox[7] hitboxes;
    
    bool canGrowl = true;
    float growlTimer = 0.0f;
    
    float footstepTimer = 0.0f;
    uint footstepIndex = 0;
    float footstepFactor = 0.0f;
    
    Entity blood;
    Emitter bloodEmitter;
    float shootDebrisTimer = 0.0f;
    
    float health = 5.0f;
    
    DemonState state = DemonState.Taunt;
    
    int stepFrame1 = 9;
    int stepFrame2 = 24;
    
    float animationSwitchTimer = 0.0f;
    
    float currentTurnAngle = 0.0f;
    
    JoltSphereShape sensorShape;
    
    JoltCharacterController character;
    
    Vector3f velocity = Vector3f(0.0f, 0.0f, 0.0f);
    Vector3f acceleration = Vector3f(0.0f, 0.0f, 0.0f);
    Vector3f lastDirection = Vector3f(0.0f, 0.0f, 1.0f);
    float maxSpeed = 9.0f;
    float positionY = 0.0f;
    
    this(GameScene scene, GLTFAsset asset, Owner owner)
    {
        super(scene.eventManager, owner);
        this.scene = scene;
        this.asset = asset;
        
        sfxFootsteps[0] = scene.audio.loadSound("assets/sounds/heavy_footstep1.wav");
        sfxFootsteps[1] = scene.audio.loadSound("assets/sounds/heavy_footstep2.wav");
        sfxGrowl[0] = scene.audio.loadSound("assets/sounds/growl1.wav");
        sfxGrowl[1] = scene.audio.loadSound("assets/sounds/growl2.wav");
        sfxGrowl[2] = scene.audio.loadSound("assets/sounds/growl3.wav");
        sfxTauntGrowl = scene.audio.loadSound("assets/sounds/growl4.wav");
        sfxDamageGrowl = scene.audio.loadSound("assets/sounds/growl5.wav");
        sfxDyingGrowl = scene.audio.loadSound("assets/sounds/growl6.wav");
        
        entity = scene.addEntity();
        entity.position = Vector3f(-8.0f, 0.0f, 0.0f);
        
        character = New!JoltCharacterController(eventManager, scene.physicsWorld, entity, 3.0f, 0.5f, 100.0f);
        
        scene.useEntity(asset.rootEntity, true);
        asset.rootEntity.setParent(entity);
        asset.rootEntity.scaling = Vector3f(2.5f, 2.5f, 2.5f);
        asset.rootEntity.position = Vector3f(0.0f, -0.15f, 0.0f);
        
        material = asset.materials[0];
        
        auto nDemon = asset.node("demon");
        pose = New!GLTFBlendedPose(nDemon.skin, this);
        animSwipe = asset.animation("swiping");
        animTaunt = asset.animation("taunt");
        animDying = asset.animation("dying");
        animHit = asset.animation("hit");
        animPunch = asset.animation("punch");
        animWalk1 = asset.animation("walk1");
        pose.switchToAnimation(animTaunt, 0.0f, PlayMode.Once);
        nDemon.entity.pose = pose;
        
        Entity rightArmCollider = scene.addEntity(asset.node("right_arm").entity);
        rightArmCollider.position = Vector3f(0.0f, 0.1f, -0.05f);
        //rightArmCollider.drawable = New!ShapeBox(Vector3f(0.06f, 0.15f, 0.06f), this);
        hitboxes[0] = CharacterHitbox(rightArmCollider, Vector3f(0.06f, 0.15f, 0.06f), 0.25f);
        
        Entity leftArmCollider = scene.addEntity(asset.node("left_arm").entity);
        leftArmCollider.position = Vector3f(-0.01f, 0.0f, -0.01f);
        //leftArmCollider.drawable = New!ShapeBox(Vector3f(0.06f, 0.15f, 0.06f), this);
        hitboxes[1] = CharacterHitbox(leftArmCollider, Vector3f(0.06f, 0.15f, 0.06f), 0.25f);
        
        Entity rightForearmCollider = scene.addEntity(asset.node("right_forearm").entity);
        rightForearmCollider.position = Vector3f(0.0f, 0.17f, -0.05f);
        //rightForearmCollider.drawable = New!ShapeBox(Vector3f(0.06f, 0.17f, 0.06f), this);
        hitboxes[2] = CharacterHitbox(rightForearmCollider, Vector3f(0.06f, 0.17f, 0.06f), 0.25f);
        
        Entity leftForearmCollider = scene.addEntity(asset.node("left_forearm").entity);
        leftForearmCollider.position = Vector3f(-0.05f, 0.15f, 0.0f);
        //leftForearmCollider.drawable = New!ShapeBox(Vector3f(0.06f, 0.17f, 0.06f), this);
        hitboxes[3] = CharacterHitbox(leftForearmCollider, Vector3f(0.06f, 0.17f, 0.06f), 0.25f);
        
        Entity headCollider = scene.addEntity(asset.node("head").entity);
        headCollider.position = Vector3f(-0.04f, 0.1f, 0.02f);
        //headCollider.drawable = New!ShapeBox(Vector3f(0.1f, 0.1f, 0.1f), this);
        hitboxes[4] = CharacterHitbox(headCollider, Vector3f(0.1f, 0.1f, 0.1f), 1.0f);
        
        Entity torsoCollider = scene.addEntity(asset.node("spine1").entity);
        torsoCollider.position = Vector3f(-0.04f, 0.17f, 0.0f);
        //torsoCollider.drawable = New!ShapeBox(Vector3f(0.2f, 0.1f, 0.13f), this);
        hitboxes[5] = CharacterHitbox(torsoCollider, Vector3f(0.2f, 0.1f, 0.13f), 0.75f);
        
        Entity spineCollider = scene.addEntity(asset.node("hips").entity);
        spineCollider.position = Vector3f(-0.04f, 0.05f, 0.05f);
        //spineCollider.drawable = New!ShapeBox(Vector3f(0.14f, 0.2f, 0.1f), this);
        hitboxes[6] = CharacterHitbox(spineCollider, Vector3f(0.14f, 0.2f, 0.1f), 0.5f);
        
        // TODO: leg hitboxes
        
        sensorShape = New!JoltSphereShape(0.75f, this);
        
        auto sphere = New!ShapeSphere(0.75f, this);
        foreach(ref s; sensors)
        {
            s = scene.addEntity();
            s.drawable = sphere;
            s.hide();
        }
        
        blood = scene.addEntity();
        bloodEmitter = New!Emitter(blood, scene.particleSystem, 10);
        bloodEmitter.material = scene.mParticlesBlood;
        bloodEmitter.startColor = Color4f(1.0f, 0.0f, 0.0f, 1.0f);
        bloodEmitter.endColor = Color4f(1.0f, 0.0f, 0.0f, 0.0f);
        bloodEmitter.initialDirectionRandomFactor = 1.0f;
        bloodEmitter.initialPositionRandomRadii = Vector3f(0.5f, 0.5f, 0.5f);
        bloodEmitter.scaleStep = Vector2f(2.0f, 2.0f);
        bloodEmitter.rotationStep = 0.5f;
        bloodEmitter.minInitialSpeed = 2.0f;
        bloodEmitter.maxInitialSpeed = 5.0f;
        bloodEmitter.minSize = 0.5f;
        bloodEmitter.maxSize = 1.0f;
        bloodEmitter.fadeInDuration = 0.01f;
        bloodEmitter.minLifetime = 0.5f;
        bloodEmitter.maxLifetime = 1.0f;
        bloodEmitter.gravity = Vector3f(0.0f, -5.0f, 0.0f);
        bloodEmitter.reset();
        bloodEmitter.emitting = false;
        blood.visible = true;
        
        pose.play();
        scene.audio.play(sfxTauntGrowl);
    }
    
    void seek(Vector3f target, float weight = 1.0f)
    {
        Vector3f desiredVeclocity = (target - entity.position).normalized * maxSpeed;
        Vector3f force = desiredVeclocity - velocity;
        acceleration += force * weight;
    }
    
    void arrive(Vector3f target, float slowingRadius, float weight = 1.0f)
    {
        float speed = maxSpeed * (distance(entity.position, target) / slowingRadius);
        Vector3f desiredVeclocity = (target - entity.position).normalized * speed;
        Vector3f force = desiredVeclocity - velocity;
        acceleration += force * weight;
    }
    
    void arriveToDistance(Vector3f target, float dist, float slowingRadius, float weight = 1.0f)
    {
        float d = distance(entity.position, target);
        if (d > dist || d < dist)
        {
            float distDelta = d - dist;
            Vector3f dir = (target - entity.position).normalized;
            dir.y = 0.0f;
            float speed = maxSpeed * (distDelta / slowingRadius);
            Vector3f desiredVeclocity = dir * speed;
            Vector3f force = desiredVeclocity - velocity;
            acceleration += force * weight;
        }
    }
    
    Vector3f direction()
    {
        float len = velocity.length;
        if (len > 0.001f)
            lastDirection = velocity / len;
        return lastDirection;
    }
    
    bool hitTest(Vector3f rayStart, Vector3f rayDirection, float rayDistance, out Vector3f hitPosition, out float damage)
    {
        Vector3f rayEnd = rayStart + rayDirection * rayDistance;
        
        bool result = false;
        hitPosition = rayEnd;
        
        float intersectionTime = 0.0f;
        damage = 0.0f;
        foreach(ref hitbox; hitboxes)
        {
            AABB aabb = AABB(Vector3f(0.0f, 0.0f, 0.0f), hitbox.halfExtents);
            Vector3f rayStartLocal = rayStart * hitbox.entity.invAbsoluteTransformation;
            Vector3f rayEndLocal = rayEnd * hitbox.entity.invAbsoluteTransformation;
            if (aabb.intersectsSegment(rayStartLocal, rayEndLocal, intersectionTime))
            {
                result = true;
                damage = hitbox.damageRatio;
                hitPosition = rayStart + rayDirection * (rayDistance * intersectionTime);
                break;
            }
        }
        
        return result;
    }
    
    void hit(Vector3f hitPosition, float damage)
    {
        blood.position = hitPosition;
        bloodEmitter.emitting = true;
        shootDebrisTimer = 1.0f;
        
        if (state != DemonState.Defeated && state != DemonState.Damage)
        {
            material.emissionTexture = null;
            material.emissionFactor = Color4f(1.0f, 0.0f, 0.0f, 1.0f);
            material.emissionEnergy = 0.5f;
            
            health -= damage;
            
            if (health <= 0.0f)
            {
                health = 0.0f;
                scene.audio.play(sfxDyingGrowl);
                state = DemonState.Defeated;
                pose.switchToAnimation(animDying, 0.5f, PlayMode.OnceAndStop);
            }
            else
            {
                scene.audio.play(sfxDamageGrowl);
                state = DemonState.Damage;
                pose.switchToAnimation(animHit, 0.05f, PlayMode.Once);
                animationSwitchTimer = 0.0f;
            }
        }
    }
    
    Entity[3] sensors;
    
    Vector3f[] sensorPositions = [
        Vector3f(0.0f, 0.0f, 1.0f),
        Vector3f(1.0f, 0.0f, 1.0f).normalized,
        Vector3f(-1.0f, 0.0f, 1.0f).normalized
        //Vector3f(1.0f, 0.0f, 0.0f),
        //Vector3f(-1.0f, 0.0f, 0.0f)
    ];
    
    void update(Time t)
    {
        if (state == DemonState.Walk)
        {
            maxSpeed = 3.5f;
            
            Vector3f lookDir = (scene.eCharacter.position - entity.position).normalized;
            
            Vector3f sensorPos = entity.position + Vector3f(0.0f, 1.75f, 0.0f);
            bool sensorTest = true;
            foreach(i, pos; sensorPositions)
            {
                sensorPos = entity.position + entity.rotation.rotate(pos * 3.0f);
                sensorPos.y += 1.75f;
                sensors[i].position = sensorPos;
                
                if (sensorTest)
                if (!scene.physicsWorld.collideShape(sensorShape, sensorPos, Quaternionf.identity, Vector3f(1.0f, 1.0f, 1.0f)))
                {
                    if (i > 0)
                        lookDir = direction;
                    Vector3f targetPosition = entity.position + entity.rotation.rotate(pos * 3.0f);
                    targetPosition.y += 1.75f;
                    arriveToDistance(targetPosition, 3.0f, 0.5f, 0.1f);
                    sensorTest = false;
                }
            }
            
            float speed = velocity.length;
            pose.timeScale = 1.0f;
            
            float desiredAngleY = radtodeg(atan2(lookDir.x, lookDir.z));
            float deltaAngle = wrapAngle(desiredAngleY - currentTurnAngle); // [-180, +180]
            const float maxTurn = 60.0f * t.delta; // 60 degrees/s
            deltaAngle = clamp(deltaAngle, -maxTurn, maxTurn);

            currentTurnAngle += deltaAngle;
            entity.setRotation(0.0f, currentTurnAngle, 0.0f);
            
            int frame = cast(int)floor(fmod(pose.time.elapsed, pose.animationDuration) * 24);
            if (frame == stepFrame1 && footstepIndex == 0)
            {
                auto voice = scene.audio.playAtPosition(sfxFootsteps[footstepIndex], entity.position);
                scene.audio.setAttenuation(voice, AttenuationModel.ExponentialDistance, 0.1f);
                footstepIndex = 1;
            }
            if (frame == stepFrame2 && footstepIndex == 1)
            {
                auto voice = scene.audio.playAtPosition(sfxFootsteps[footstepIndex], entity.position);
                scene.audio.setAttenuation(voice, AttenuationModel.ExponentialDistance, 0.1f);
                footstepIndex = 0;
            }
            
            if (distance(entity.position, scene.eCharacter.position) <= 2.0f)
            {
                if (canGrowl)
                {
                    scene.audio.playAtPosition(sfxGrowl[uniform(0, $)], entity.position);
                    canGrowl = false;
                }
                
                state = DemonState.Attack;
                pose.switchToAnimation(animPunch, 0.15f, PlayMode.Loop);
                pose.timeScale = 1.0f;
            }
        }
        else if (state == DemonState.Damage)
        {
            velocity = Vector3f(0.0f, 0.0f, 0.0f);
            acceleration = Vector3f(0.0f, 0.0f, 0.0f);
            animationSwitchTimer += t.delta;
            if (animationSwitchTimer > 1.0f)
            {
                int frame = cast(int)floor(fmod(pose.time.elapsed, pose.animationDuration) * 24);
                if (frame >= 30)
                {
                    state = DemonState.Walk;
                    pose.switchToAnimation(animWalk1, 0.15f, PlayMode.Loop);
                    footstepIndex = 0;
                    animationSwitchTimer = 0.0f;
                    pose.timeScale = 1.0f;
                }
            }
        }
        else if (state == DemonState.Taunt)
        {
            velocity = Vector3f(0.0f, 0.0f, 0.0f);
            acceleration = Vector3f(0.0f, 0.0f, 0.0f);
            animationSwitchTimer += t.delta;
            if (animationSwitchTimer > 1.0f)
            {
                int frame = cast(int)floor(fmod(pose.time.elapsed, pose.animationDuration) * 24);
                if (frame >= 60)
                {
                    state = DemonState.Walk;
                    pose.switchToAnimation(animWalk1, 0.25f, PlayMode.Loop);
                    footstepIndex = 0;
                    animationSwitchTimer = 0.0f;
                    pose.timeScale = 1.0f;
                }
            }
        }
        else if (state == DemonState.Attack)
        {
            velocity = Vector3f(0.0f, 0.0f, 0.0f);
            acceleration = Vector3f(0.0f, 0.0f, 0.0f);
            pose.timeScale = 1.0f;
            
            if (distance(entity.position, scene.eCharacter.position) > 3.0f)
            {
                state = DemonState.Walk;
                pose.switchToAnimation(animWalk1, 0.15f, PlayMode.Loop);
                footstepIndex = 0;
                animationSwitchTimer = 0.0f;
                pose.timeScale = 1.0f;
            }
            
            Vector3f lookDir = (scene.eCharacter.position - entity.position).normalized;
            
            float desiredAngleY = radtodeg(atan2(lookDir.x, lookDir.z));
            float deltaAngle = wrapAngle(desiredAngleY - currentTurnAngle); // [-180, +180]
            const float maxTurn = 270.0f * t.delta; // 270 degrees/s
            deltaAngle = clamp(deltaAngle, -maxTurn, maxTurn);

            currentTurnAngle += deltaAngle;
            entity.setRotation(0.0f, currentTurnAngle, 0.0f);
        }
        else
        {
            velocity = Vector3f(0.0f, 0.0f, 0.0f);
            acceleration = Vector3f(0.0f, 0.0f, 0.0f);
            pose.timeScale = 1.0f;
        }
        
        velocity += acceleration;
        velocity = velocity.normalized * clamp(velocity.length, -maxSpeed, maxSpeed);
        acceleration = Vector3f(0.0f, 0.0f, 0.0f);
        
        character.move(velocity);
        
        if (growlTimer < 5.0f && !canGrowl)
        {
            growlTimer += t.delta;
        }
        else
        {
            canGrowl = true;
            growlTimer = 0.0f;
        }
        
        if (material.emissionEnergy > 0.0f)
        {
            material.emissionEnergy -= t.delta;
        }
        else
        {
            material.emissionEnergy = 0.0f;
        }
        
        pose.update(t);
        blood.update(t);
        
        if (shootDebrisTimer > 0.0f)
            shootDebrisTimer -= 20.0f * t.delta;
        else
        {
            shootDebrisTimer = 0.0f;
            bloodEmitter.emitting = false;
        }
    }
}
