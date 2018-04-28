---
layout: post
title: "Advanced Ember Data Customization - Different Model Types in Ember App and API For The Same Resource"
date: 2018-04-28 19:00
comments: true
categories: [Ember, Ember Data]
---


A **great advantage** of using **Ember Data** with **JSONAPI-compliant** adapters/serializers is that there is almost nothing extra needed to work with the **data layer** - just create the models with names matching the types of the resources returned by the **API** and you are good to go! However, sometimes you may need to customize the naming which means that the names of the models in the **Ember application** will be different than the ones expected by the API and their corresponding types. What are the steps required to make it work in **Ember Data**?

<!--more-->

## Anatomy Of The Problem

Imagine that the API you work with has two resources: `User` and `Picture` and that a User can have many Pictures. However, in the Ember application, you want to have these resources named as `Photographer` and `Photo`. Here are the models and relationships between them:

``` js
// app/models/photographer.js
import Model from 'ember-data/model';
import { hasMany } from 'ember-data/relationships';

export default Model.extend(MessageSender, {
  photos: hasMany('photo')
});
```

``` js
// app/models/photo.js
import Model from 'ember-data/model';
import { belongsTo } from 'ember-data/relationships';

export default Model.extend({
  photographer: belongsTo('photographer')
});
```

## The Solution

Unfortunately, models' names don't follow the naming expected by the API. There are a couple of things that we need to customize here:

1. Endpoints for a given resource - by default, for `Photographer` model, all requests will be performed to `/photographers` endpoint. We need to make it work with `/users` endpoint. Same thing with `Photo` model.
2. Serialization of the models - for `Photographers` we will need to make sure that `users` type is present in the payload, not `photographers` and the same thing for `pictures` vs. `photos`.
3. Normalization of the payload from the API - we need to map `user` type to `photographer` and `picture` type to `photo`.
4. Handle the relationship between `Photographer` and `Photo` with proper types.

Let's handle each case one by one.

The first one is quite straightforward - we need to adjust adapters for both models. According to the [docs](https://guides.emberjs.com/v3.0.0/models/customizing-adapters/#toc_path-customization), `pathForType` method is the one that we care about. Since we are just going to change the type, not the actual logic that happens to that type later, we can handle these adjustments the following way:

``` js
// app/adapters/application.js
import DS from 'ember-data';

export default DS.JSONAPIAdapter.extend();
```


``` js
// app/adapters/photographer.js
import ApplicationAdapter from './application';

export default ApplicationAdapter.extend({
  pathForType() {
    return this._super('user');
  }
});
```


``` js
// app/adapters/photo.js
import ApplicationAdapter from './application';

export default ApplicationAdapter.extend({
  pathForType() {
    return this._super('picture');
  }
});
```

The first part is done. Let's focus now on the serialization. After a bit of research of the docs and the source code, it looks like `payloadKeyFromModelName` needs to be customized. In this case, we just want to make sure that `photographer` type is mapped to `user`, and `photo` is mapped to `picture`. As this is arguably a less straightforward change than overriding `pathForType` in adapters, it might make sense to write some unit tests for that. Fortunately, it's nothing too complex - just comparing the serialization result with the expected one. Let's write a test for `ApplicationSerializer`:

``` js
// tests/unit/serializers/application-test.js
import { module, test } from 'qunit';
import { setupTest } from 'ember-qunit';
import { run } from '@ember/runloop';

module('Unit | Serializer | application', function(hooks) {
  setupTest(hooks);

  module('serialize', function() {
    module('photographer', function() {
      test('it is serialized according to remapped naming', function(assert) {
        assert.expect(1);

        let store = this.owner.lookup('service:store');

        run(() => {
          let model = store.createRecord('photographer', {});
          let payload = model.serialize();

          assert.equal(payload.data.type, 'users');
        });
      });
    });

    module('photo', function() {
      test('it is serialized according to its naming', function(assert) {
        assert.expect(1);

        let store = this.owner.lookup('service:store');

        run(() => {
          let model = store.createRecord('photo', {});
          let payload = model.serialize();

          assert.equal(payload.data.type, 'pictures');
        });
      });
    });
  });
});
```

Since we are interested only in a type remapping, we don't check the entire payload, only `type` attribute. Let's make these tests pass by either remapping types or using the default logic:

``` js
// app/serializers/application.js
import DS from 'ember-data';

const keysMappingForSerialization = {
  'photographer': 'user',
  'photo': 'picture'
};

export default DS.JSONAPISerializer.extend({
  payloadKeyFromModelName(key) {
    if (keysMappingForSerialization[key]) {
      return this._super(keysMappingForSerialization[key]);
    } else {
      return this._super(...arguments);
    }
  }
});
```

Awesome, we are almost there.

Both third and fourth points are actually about normalization, so we are going to handle them together. Again, after some research, it looks like we need to customize `modelNameFromPayloadKey` to map types returned by API to corresponding types in our app and also override `keyForRelationship` method to handle relationships in the payload correctly. Again, let's start with some tests. The simplest way to test such things is checking the result of [normalizeResponse](https://emberjs.com/api/ember-data/3.0/classes/DS.JSONAPISerializer/methods/normalizeResponse?anchor=normalizeResponse) for some request type, e.g., for 'findAll'. Let's write a test for a more complex scenario including relationships and sideloading as well:

``` js
// tests/unit/serializers/application-test.js
import { module, test } from 'qunit';
import { setupTest } from 'ember-qunit';
import { run } from '@ember/runloop';

module('Unit | Serializer | application', function(hooks) {
  setupTest(hooks);

  module('serialize', function() {
    // previous tests
  });

  module('normalizeResponse', function() {
    module('photographer', function() {
      test('it is normalized according to remapped naming', function(assert) {
        assert.expect(1);

        let store = this.owner.lookup('service:store');
        let serializer = store.serializerFor('photographer');

        run(() => {
          let payload = {
            'data': {
              'type': 'users',
              'id': '1',
              'attributes': {},
              'relationships': {
                'pictures': {
                  'links': {
                    'self': 'https://host.test/api/v1/users/1/relationships/pictures',
                    'related': 'https://host.test/api/v1/users/1/pictures'
                  },
                  'data': [{ 'type': 'pictures', 'id': '10' }]
                }
              }
            },
            'included': [
              {
                'type': 'pictures',
                'id': '10',
                'attributes': {},
                'links': {
                  'self': 'https://host.test/api/v1/pictures/10'
                }
              }
            ]
          };

          let normalizedPayload = serializer.normalizeResponse(store, store.modelFor('photographer'),
            payload, 1, 'findAll');
          let expectedPayload = {
            'data': {
              'attributes': {},
              'id': '1',
              'relationships': {
                'emails': {
                  'data': [
                    { 'id': '10', 'type': 'photos' }
                  ],
                  'links': {
                    'self': 'https://host.test/api/v1/users/1/relationships/pictures',
                    'related': 'https://host.test/api/v1/users/1/pictures'
                  }
                }
              },
              'type': 'photographer'
            },
            'included': [
              {
                'attributes': {},
                'id': '10',
                'relationships': {},
                'type': 'photo'
              }
            ]
          };

          assert.deepEqual(normalizedPayload, expectedPayload);
        });
      });
    });

    module('photo', function() {
      test('it is normalized according to remapped naming', function(assert) {
        assert.expect(1);

        let store = this.owner.lookup('service:store');
        let serializer = store.serializerFor('photo');

        run(() => {
          let payload = {
            'data': {
              'type': 'pictures',
              'id': '1',
              'attributes': {},
              'relationships': {
                'user': {
                  'links': {
                    'self': 'https://host.test/api/v1/pictures/1/relationships/user',
                    'related': 'https://host.test/api/v1/pictures/1/user'
                  },
                  'data': { 'type': 'users', 'id': '10' }
                }
              }
            },
            'included': [
              {
                'type': 'users',
                'id': '10',
                'attributes': {},
                'links': {
                  'self': 'https://host.test/api/v1/users/10'
                }
              }
            ]
          };

          let normalizedPayload = serializer.normalizeResponse(store, store.modelFor('photo'),
            payload, 1, 'findAll');
          let expectedPayload = {
            'data': {
              'attributes': {},
              'id': '1',
              'relationships': {
                'photographer': {
                  'data': { 'id': '10', 'type': 'photographer' },
                  'links': {
                    'related': 'https://host.test/api/v1/pictures/1/user',
                    'self': 'https://host.test/api/v1/pictures/1/relationships/user'
                  }
                }
              },
              'type': 'photo'
            },
            'included': [
              {
                'attributes': {},
                'id': '10',
                'relationships': {},
                'type': 'photographer'
              }
            ]
          };

          assert.deepEqual(normalizedPayload, expectedPayload);
        });
      });
    });
  });
});
```


First, let's make it work with nonrelationship-related part, i.e. `modelNameFromPayloadKey` customization:

``` js
// app/serializers/application.js
import DS from 'ember-data';

const keysMappingForSerialization = {
  'photographer': 'user',
  'photo': 'picture'
};

const keysMappingForNormalization = {
  'users': 'photographers',
  'pictures': 'photos'
};

export default DS.JSONAPISerializer.extend({});
  payloadKeyFromModelName(key) {
    if (keysMappingForSerialization[key]) {
      return this._super(keysMappingForSerialization[key]);
    } else {
      return this._super(...arguments);
    }
  },

  modelNameFromPayloadKey(modelName) {
    if (keysMappingForNormalization[modelName]) {
      return this._super(keysMappingForNormalization[modelName]);
    } else {
      return this._super(...arguments);
    }
  }
});
```

Again, the same pattern as before - for whitelisted types we want to remap them and apply the default logic for the rest of the types.

And to handle the relationships we can customize the serializers separately:

``` js
// app/serializers/photographer.js
import ApplicationSerializer from './application';

const keysForRelationshipsMapping = {
  'photographer': 'user'
};

export default ApplicationSerializer.extend({
  keyForRelationship(key) {
    if (keysForRelationshipsMapping[key]) {
      return this._super(keysForRelationshipsMapping[key]);
    } else {
      return this._super(...arguments);
    }
  }
});
```

``` js
// app/serializers/photo.js
import ApplicationSerializer from './application';

const keysForRelationshipsMapping = {
  'photo': 'picture'
};

export default ApplicationSerializer.extend({
  keyForRelationship(key) {
    if (keysForRelationshipsMapping[key]) {
      return this._super(keysForRelationshipsMapping[key]);
    } else {
      return this._super(...arguments);
    }
  }
});
```

And that's it! All our tests are green, and the models are going to work with the API!

## Wrapping Up

Thanks to a **solid design** of **Ember Data**, it's quite simple to customize the **data layer** which in most cases requires merely overriding a couple of methods.
