module steering;

import dlib.math.utils;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;

import dagon.core.time;
import dagon.core.event;
import dagon.graphics.entity;

class Steering: EntityComponent
{
    Vector3f velocity = Vector3f(0.0f, 0.0f, 0.0f);
    Vector3f acceleration = Vector3f(0.0f, 0.0f, 0.0f);
    Vector3f lastDirection = Vector3f(0.0f, 0.0f, 1.0f);
    float maxSpeed = 9.0f;
    float positionY = 0.0f;

    this(EventManager eventManager, Entity hostEntity)
    {
        super(eventManager, hostEntity);
    }
    
    override void update(Time time)
    {
        velocity += acceleration;
        velocity = velocity.normalized * clamp(velocity.length, -maxSpeed, maxSpeed);
        entity.position += velocity * time.delta;
        entity.position.y = positionY;
        acceleration = Vector3f(0.0f, 0.0f, 0.0f);

        entity.transformation =
            translationMatrix(entity.position) *
            entity.rotation.toMatrix4x4 *
            scaleMatrix(entity.scaling);
        entity.invTransformation = entity.transformation.inverse;

        entity.absoluteTransformation = entity.transformation;
        entity.invAbsoluteTransformation = entity.invTransformation;
        entity.prevAbsoluteTransformation = entity.prevTransformation;
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
}
