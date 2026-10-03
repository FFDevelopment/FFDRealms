# Implementation API references

The source remains on the project's existing Godot 4.3 API baseline; this is not a recommendation to downgrade your editor. Native compilation was not available here. References retained for the appearance implementation:

- ColorPickerButton (`color`, `edit_alpha`, `color_changed`): https://docs.godotengine.org/en/4.3/classes/class_colorpickerbutton.html
- Color (`html_is_valid`, string construction, `to_html`): https://docs.godotengine.org/en/4.3/classes/class_color.html
- BaseMaterial3D (albedo texture/color, texture filters, roughness/specular): https://docs.godotengine.org/en/4.3/classes/class_basematerial3d.html
- SubViewport (size, render-target update modes): https://docs.godotengine.org/en/4.3/classes/class_subviewport.html
- Viewport (isolated 3D world): https://docs.godotengine.org/en/4.3/classes/class_viewport.html

Reference pages verify API names, not this project's compilation, runtime behavior, UI layout, or visual quality.

## 0.2.2 combat implementation references

Checked against the same existing 4.3 API baseline, not a claim about the latest engine release:

- Vector3 (`normalized`, `dot`, `is_finite`, `move_toward`): https://docs.godotengine.org/en/4.3/classes/class_vector3.html
- ArrayMesh (`add_surface_from_arrays`, vertex arrays): https://docs.godotengine.org/en/4.3/classes/class_arraymesh.html
- InputEventWithModifiers (`shift_pressed`): https://docs.godotengine.org/en/4.3/classes/class_inputeventwithmodifiers.html
- BaseMaterial3D (unshaded, cull mode and alpha transparency): https://docs.godotengine.org/en/4.3/classes/class_basematerial3d.html

The official 4.3 archive/download endpoint was inspected while attempting to obtain a test executable. The download did not produce a usable engine; native execution remains NOT RUN.

## 0.2.3 texture implementation references

Checked against the existing API baseline, not a recommendation to change editor version:

- BaseMaterial3D: albedo/normal textures, triplanar mapping, roughness/specular and anisotropic mipmapped filtering: https://docs.godotengine.org/en/4.3/classes/class_basematerial3d.html
- Spatial shaders: sampler declarations, VERTEX, ALBEDO, NORMAL_MAP, NORMAL_MAP_DEPTH, ROUGHNESS and SPECULAR: https://docs.godotengine.org/en/4.3/tutorials/shaders/shader_reference/spatial_shader.html

API references verify documented identifiers, not this game's compilation or appearance. The executable download attempt for this build did not produce a usable Godot engine.


## 0.3.0 terrain implementation references

The existing 4.3 API baseline was retained (not a recommendation to downgrade). Consulted primary documentation:

- ArrayMesh, attribute arrays and clockwise winding: https://docs.godotengine.org/en/4.3/classes/class_arraymesh.html
- Mesh, `create_trimesh_shape`, `get_faces`, normal/tangent/UV arrays: https://docs.godotengine.org/en/4.3/classes/class_mesh.html

The mesh and collider use the same triangles. Reference checks do not establish native compiler or shader success. Native test execution remains NOT RUN in this build environment.
