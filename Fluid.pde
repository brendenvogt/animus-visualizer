import ddf.minim.*; 

class Fluid extends Visualizer {
    @Override
    int getOptimalFrameRate() {
        return 40;
    }

    final int SPEC_SIZE = 30;
    final float SPEC_WIDTH = 5;
    final int HORIZ_SAMPLE_NUM = 80;
    final int VERT_SAMPLE_NUM = 30;
    final int REFRESH = 3;
    final float ANGLE_INC = 0.001;
    final float MIN_PARTICLE_SIZE = 2;
    final float MAX_PARTICLE_SIZE = 20;

    // since we need 4 different color trackers -- base and peak colors for both
    // bottom and top halves -- stored all dem in an array
    // colorTrackers[0] -> base tracker for bottom half
    // colorTrackers[1] -> peak tracker for bottom half
    // colorTrackers[2] -> base tracker for top half
    // colorTrackers[3] -> peak tracker for top half
    ColorTracker[] colorTrackers;
    
    HorizSample[] horizSamples;
    VertSample[] vertSamples;
    
    float currRot = 0;

    int particleDetailLoss = 1;
    
    Fluid(AudioInput input) {
        super(input, "FLUID");
        colorTrackers = new ColorTracker[4];
        for (int i = 0; i < colorTrackers.length; i++) {
            colorTrackers[i] = new ColorTracker(0.5, 4);   
        }
        camera.setCenter(SPEC_SIZE * SPEC_WIDTH, 0, 0);
        horizSamples = new HorizSample[HORIZ_SAMPLE_NUM];
        vertSamples = new VertSample[VERT_SAMPLE_NUM];
        for (int i = 0; i < horizSamples.length; i++) {
            horizSamples[i] = new HorizSample(i * REFRESH, REFRESH, HORIZ_SAMPLE_NUM * REFRESH);
        }
        for (int i = 0; i < vertSamples.length; i++) {
            vertSamples[i] = new VertSample(i * REFRESH, REFRESH, VERT_SAMPLE_NUM * REFRESH);
        }
        camera.viewingMode = false;
        camera.pos = new PVector(SPEC_SIZE * SPEC_WIDTH, 0, -130);
        camera.setOuterBounds(0, -200, -200, SPEC_SIZE * SPEC_WIDTH * 2, 200, REFRESH * HORIZ_SAMPLE_NUM);
        noFill();
    }

    class Point {
        float x, y, z, intensity;

        // we are re-using the same samples to draw both bottom and top - but bottom and top need
        // different NON-COMPLEMENTARY colors. so each point keeps track of the two set of colors
        // it will display as
        float[] topColors;
        float[] botColors;

        public Point(float x, float y, float z) {
            this.x = x;
            this.y = y;
            this.z = z;
            topColors = new float[4];
            botColors = new float[4];
        }
    }

    class HorizSample {
        float pos, speed, stop;
        int index;
        Point[] points;

        HorizSample(float initPos, float speed, float stop) {
            this.speed = speed;
            this.stop = stop;
            index = (int) (initPos / speed);
            pos = initPos;
            points = new Point[SPEC_SIZE * 2];
            for (int i = 0; i < points.length; i++) {
                points[i] = new Point(i * SPEC_WIDTH, 0, 0);
            }
        }
        
        void setColor(float fade, float[] colors) {
            stroke(colors[0] * fade, colors[1] * fade, colors[2] * fade);
        }        

        void update() {
            pos += speed;  
            if (expand) {
                for (int i = 0; i < points.length; i++) {
                    points[i].y += pos / 40;
                }
            }
            if (pos >= stop) {
                for (int i = 0; i < points.length; i++) {
                    int fftIndex = abs(points.length / 2 - i);
                    points[i].y = getIntensity(fftIndex);
                    points[i].intensity = getIntensity(fftIndex);

                    // see comment inside Point (above botColors and topColors)
                    // for explanation on wtf is going on here
                    points[i].botColors = getColor(points[i].intensity, 40, colorTrackers[0], colorTrackers[1]);
                    points[i].topColors = getColor(points[i].intensity, 40, colorTrackers[2], colorTrackers[3]);
                }
                pos = 0;
            }
        }

        void drawLines(int ydir, float fade) {
            pushMatrix();

            if (pos > 0) {

                HorizSample currSample = this;
                int prevIndex;
                if (index == 0) {
                    prevIndex = horizSamples.length - 1;
                } else {
                    prevIndex = index - 1;
                }

                HorizSample prevSample = horizSamples[prevIndex];

                // strokeWeight cannot being changed while inside beginShape/endShape,
                // so we must use point() instead of vertex() when drawing particles
                if (!particles) {
                    beginShape(QUAD_STRIP);
                }

                float zEnd = prevSample.pos;
                float zStart = currSample.pos;
                for (int i = 0; i < points.length; i++) {
                    float xStart = currSample.points[i].x;
                    float xEnd = prevSample.points[i].x;
                    float yStart = currSample.points[i].y * ydir;
                    float yEnd = prevSample.points[i].y * ydir;
                    
                    if (ydir > 0) {
                        setColor(fade, points[i].botColors);
                    } else {
                        setColor(fade, points[i].topColors);
                    }

                    if (!particles) {
                        vertex(xStart, yStart, zStart);
                        vertex(xEnd, yEnd, zEnd);
                    } else if (i % particleDetailLoss == 0) {
                        strokeWeight(bindRange(currSample.points[i].intensity, MIN_PARTICLE_SIZE, MAX_PARTICLE_SIZE));
                        point(xStart, yStart, zStart);
                    }
                }  

                if (!particles) {
                    endShape();
                }
            } 
            popMatrix();
        }
    }

    class VertSample {
        float pos, stop, speed;
        PVector[] points;
        boolean continueSampling;

        VertSample(float initPos, float speed, float stop) {
            pos = initPos;
            this.speed = speed;
            this.stop = stop;
            points = new PVector[SPEC_SIZE * 2];
            for (int i = 0; i < points.length; i++) {
                points[i] = new PVector(i * SPEC_WIDTH, 0);
            }
            continueSampling = false;
        }

        void update() {
            pos += speed;
            if (pos >= stop) {
                for (int i = 0; i < points.length; i++) {
                    int fftIndex = abs(points.length / 2 - i);
                    points[i].y = getIntensity(fftIndex);
                }
                pos = 0;
                if (highlight) {
                    continueSampling = true;
                } else {
                    continueSampling = false;
                }
            }
        }

        void drawLines(int ydir) {
            pushMatrix();

            translate(0, pos * ydir, 0);

            if (!particles) {
                beginShape(LINES);
            }

            for (int i = 0; i < points.length - 1; i++) {
                float weight = bindRange((points[i].y + points[i + 1].y) / 20, 0.1, 6);
                if (particles) {
                    weight *= 5;
                }
                strokeWeight(weight);
                if (!particles) {
                    vertex(points[i].x, points[i].y * ydir);
                    vertex(points[i + 1].x, points[i + 1].y * ydir);
                } else {
                    point(points[i].x, points[i].y * ydir);
                }
            }

            float weight = min((points[points.length - 2].y + points[points.length - 1].y) / 20, 6);
            strokeWeight(weight);
            if (!particles) {
                vertex(points[points.length - 2].x, points[points.length - 2].y * ydir);
                vertex(points[points.length - 1].x, points[points.length - 1].y * ydir);
            } else {
                point(points[points.length - 2].x, points[points.length - 2].y * ydir);
            }

            if (!particles) {
                endShape();
            }

            popMatrix();
        }
    }

    @Override
    void draw() {
        if (blur) {
            setBackground(contrast, 50);
        } else {
            setBackground(contrast, 150);
        }
        
        camera.update();
        for (ColorTracker ct : colorTrackers) {
            ct.incrementColor();
        }
        noFill();
        pushMatrix();
    
        // makes sure vertical samples appear at the front of the figure
        if (revolve) {
            translate(0, 0, 170);
        }

        if (revolve) {
            currRot += ANGLE_INC;
        } else {
            currRot = lerp(currRot, 0, PHI * 40 * ANGLE_INC);
        }
        
        for (int i = 0; i < VERT_SAMPLE_NUM; i++) {
            vertSamples[i].update();
        }
        for (int i = 0; i < VERT_SAMPLE_NUM; i++) {
            VertSample s = vertSamples[i];
            if (s.continueSampling) {
                    rotateZ(currRot);
                float fade = 1 - s.pos / (VERT_SAMPLE_NUM * REFRESH);
                setComplementaryColor(fade, colorTrackers[0]);
                s.drawLines(1);
                setComplementaryColor(fade, colorTrackers[2]);
                s.drawLines(-1);
            }
        } 

        popMatrix();

        pushMatrix();

        strokeWeight(1);
        for (int i = 0; i < HORIZ_SAMPLE_NUM; i++) {
            horizSamples[i].update();
        }
        for (int i = 0; i < HORIZ_SAMPLE_NUM; i++) {
            HorizSample s = horizSamples[i];

            int relativeIndex = (int) (s.pos / REFRESH);
            rotateZ(currRot * relativeIndex);
            if (expand) {
                float weight = map(s.pos, 0, s.stop, 0.8, 5);
                strokeWeight(weight);
            }

            float fade;
            if (expand) {
                fade = 1 - s.pos / (HORIZ_SAMPLE_NUM * REFRESH) / 2;
            } else {
                fade = 1 - s.pos / (HORIZ_SAMPLE_NUM * REFRESH);
            }

            s.drawLines(1, fade);
            s.drawLines(-1, fade);  

            rotateZ(-currRot * relativeIndex);
        }

        popMatrix();
    }
    
    void setComplementaryColor(float fade, ColorTracker tracker) {
        stroke((255 - tracker.red) * fade, (255 - tracker.green) * fade, (255 - tracker.blue) * fade);
    }

    @Override
    void adjustDetail(float avgFr) {
        if (avgFr < 25) {
            particleDetailLoss = 5;
        } else if (avgFr < 40) {
            particleDetailLoss = 4;
        } else if (avgFr < 35) {
            particleDetailLoss = 3;
        } else if (avgFr < 38) {
            particleDetailLoss = 2;
        }
        println(particleDetailLoss);
    }

    @Override
    void particles() {
        particles = !particles;
        blur = particles;
    }

    @Override
    void highlight() {
        highlight = !highlight;
    }

    @Override
    void expand() {
        expand = !expand;
    }

    @Override
    void revolve() { 
        revolve = !revolve;
        if (!revolve && currRot >= .082) {
            currRot = .082; //sets revolve to 1 full rotation
        }
        fPressed();
        frontView();
    }

    @Override
    void frontView() {
        float camX = SPEC_SIZE * SPEC_WIDTH;
        if (revolve) {
            camera.initMoveCenter(0, 0, 0, (int)frameRate);
            camX = 0;
        } else {
            camera.initMoveCenter(SPEC_SIZE * SPEC_WIDTH, 0, 0, (int)frameRate);
        }
        camera.initMoveCamera(new PVector(camX, 0, -130), (int)frameRate);
        camera.initMoveDir(new PVector(0, 1, 0), (int) frameRate);
    }
    
    @Override
    void rearView() {
        float camX = SPEC_SIZE * SPEC_WIDTH;
        if (revolve) {
            camera.initMoveCenter(0, 0, 0, (int)frameRate);
            camX = 0;
        }
        camera.initMoveCamera(new PVector(camX, 0, 300), (int)frameRate);
        camera.initMoveDir(new PVector(0, 1, 0), (int) frameRate);
    }
    
    
    @Override
    void topView() { 
        float camZ = HORIZ_SAMPLE_NUM * REFRESH/ 1.99;
        float camY = -150;
        if (frontView) {
            camZ = HORIZ_SAMPLE_NUM * REFRESH / 2.1;
            camY = 150;
        }
        
        if (revolve) {
            camera.initMoveCamera(new PVector(-150, camY, camZ), (int) frameRate * 2);
            camera.initMoveCenter(0, 0, HORIZ_SAMPLE_NUM * REFRESH / 2, (int) frameRate / 2);
        } else {
            camera.initMoveCamera(new PVector(150, camY, camZ), (int) frameRate * 2);
            camera.initMoveCenter(SPEC_SIZE * SPEC_WIDTH, 0, HORIZ_SAMPLE_NUM * REFRESH / 2, (int) frameRate);
        }
        camera.initMoveDir(new PVector(0, 1, 0), (int) frameRate);
    }
}
