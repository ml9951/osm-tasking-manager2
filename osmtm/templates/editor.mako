# -*- coding: utf-8 -*-
<%
from geoalchemy2 import shape
import json
geometry_as_shape = shape.to_shape(task.geometry)
bounds = geometry_as_shape.bounds
project = task.project
x = json.dumps(features)
y = json.dumps(osm_features)

%>
<div id='map' style="position: absolute; top:0;left: 0; right: 0; bottom: 0">
  <button id="done-mapping" class="btn btn-default" style="position: absolute; z-index: 5000; top: 20; right:20; height:40; border-radius: 10px;background-color : #337AB7; color : white; width : 100;">
    Done Mapping
  </button>
  <button hidden id="delete-feature" class="btn btn-default" style="position: absolute; z-index: 5000; top: 70; right:20; height:40; border-radius: 10px;background-color : red; color : white; width:100;">
    Delete Feature
  </button>
  <button hidden id="add-feature" class="btn btn-default" style="position: absolute; z-index: 5000; top: 120; right:20; height:40; border-radius: 10px;background-color : green; color : white; width : 100">
    Add Feature
  </button>


</div>

<link rel="stylesheet" href="https://unpkg.com/leaflet@1.0.3/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.0.3/dist/leaflet.js"></script>
<script src="${request.static_url('osmtm:static/js/lib/Leaflet.Editable.js')}"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
<script src='https://npmcdn.com/@turf/turf/turf.min.js'></script>   

<script>
  var task_bounds = [[${bounds[1]}, ${bounds[0]}], [${bounds[3]}, ${bounds[2]}]];
  var map = L.map('map', {editable : true, scrollWheelZoom : false})
  map.fitBounds(task_bounds)
  L.tileLayer('${tile_layer}', {maxZoom: 19, tms : true}).addTo(map);
  L.rectangle(task_bounds, {color: "#ff7800", fillOpacity : 0, weight: 1}).addTo(map);

  var existingFeatures = JSON.parse(${x | n})
  var osm_features = JSON.parse(${y | n})

  var edited = {};
  var polygons = {};
  var deleted = [];
  var osm_deleted = [];

  var nextID = 0;
  var selectedPolygon = null;

  L.EditControl = L.Control.extend({
    options: {
      position: 'topleft',
      callback: null,
      kind: '',
      html: ''
    },
    onAdd: function (map) {
      var container = L.DomUtil.create('div', 'leaflet-control leaflet-bar');
      var link = L.DomUtil.create('a', '', container);
      link.href = '#';
      link.title = 'Create a new ' + this.options.kind;
      link.innerHTML = this.options.html;
      L.DomEvent.on(link, 'click', L.DomEvent.stop)
                .on(link, 'click', function () {
                  window.LAYER = this.options.callback.call(map.editTools);
                }, this);
      return container;
    }
  })
  L.NewPolygonControl = L.EditControl.extend({
    options: {
      position: 'topleft',
      callback: function(latlng){map.editTools.startPolygon(latlng, {weight : 1})},
      kind: 'polygon',
      html: '⬠'
    }
  });

  map.addControl(new L.NewPolygonControl())

  function _disableClickPropagation(element, polygon) {
    if (!L.Browser.touch || L.Browser.ie) {
      L.DomEvent.disableClickPropagation(element);
      L.DomEvent.on(element, 'mousewheel', L.DomEvent.stopPropagation);
    } else {
      L.DomEvent.on(element, 'click', function(e){
        if(selectedPolygon) selectedPolygon.disableEdit();
        selectedPolygon = polygon;
        polygon.enableEdit();
        $("#delete-feature").removeAttr("hidden");
        if(polygon.osm_id){
          $("#add-feature").removeAttr("hidden");
        }
        L.DomEvent.stopPropagation(e)
      });
    }
  }

  function plotFeatures(features, color){
    features.forEach(function(feature){
      var polygon = L.polygon(turf.flip(feature).geometry.coordinates, {color : color, weight : 1, fillOpacity : 0})
      polygon.id = feature.properties.id;

      if(feature.properties.osm_id){
        polygon.osm_id = feature.properties.osm_id
      }

      polygon.addTo(map)
      _disableClickPropagation(polygon.getElement(), polygon)

      if(polygon.osm_id == null){
        polygon.on('editable:vertex:dragend', function(){
            edited[polygon.id] = polygon;
        })
      }
    })
  }

  plotFeatures(existingFeatures, 'red')
  plotFeatures(osm_features, 'yellow')

  $("#delete-feature").click(function(e){
    if(polygons[selectedPolygon.id] == null){
      //This was a pre-existing polygon...
      if(edited[selectedPolygon.id] != null){
        //Don't send the server these edits...
        delete edited[selectedPolygon.id];
      }
      deleted.push(selectedPolygon.id);
    }else{
      delete polygons[selectedPolygon.id]
    }
    map.removeLayer(selectedPolygon)
  })

  $("#add-feature").click(function(e){
    // Delete from the OSM table and insert into the features table.
    osm_deleted.push(selectedPolygon.osm_id);
    selectedPolygon.id = nextID;
    nextID++;
    polygons[selectedPolygon.id] = selectedPolygon;

    selectedPolygon.setStyle({color : 'red'})
    selectedPolygon.disableEdit()
    selectedPolygon = null;


  })

  map.on('editable:drawing:end', function(e){
    const polygon = e.layer;
    polygon.id = nextID;
    polygons[nextID] = polygon;
    nextID++;
    _disableClickPropagation(polygon.getElement(), polygon)
  })

  map.on('editable:drawing:start', function(e){
    console.log('Started polygon')
    const polygon = e.layer;
    // polygon.disableEdit();
  })

  map.on('click', function(event){
    $("#delete-feature").attr('hidden', "true")
    $("#add-feature").attr('hidden', "true")
    if(selectedPolygon) selectedPolygon.disableEdit()
    selectedPolygon = null;
  })

  $(document).ready(function(){
    $("#done-mapping").click(function(e){
      e.preventDefault();
      e.stopPropagation();

      newFeatures = Object.keys(polygons).map(k => polygons[k].toGeoJSON());
      editedFeatures = Object.keys(edited).map(k => {
        var polygon = edited[k];
        var feature = polygon.toGeoJSON();
        feature.properties.id = polygon.id;
        return feature;
      })

      $.ajax({
        type : 'POST',
        url : "${request.route_path('features', task=task.id, project=task.project_id, user=user.id)}",
        data : JSON.stringify({
          newFeatures : newFeatures, 
          editedFeatures : editedFeatures,
          deletedIDs : deleted,
          deletedOSM : osm_deleted
        }),
        contentType: "application/json; charset=utf-8",
        dataType : "json",
        success : function(){
          history.back()
        }
      })
    })
  })

</script>

<p></p>
