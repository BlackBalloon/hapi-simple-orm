const BaseModel     = require('./lib/model/baseModel');

const BaseDAO       = require('./lib/dao/baseDao');

const BaseField     = require('./lib/fields/baseField');
const ForeignKey    = require('./lib/fields/foreignKey');
const ManyToMany    = require('./lib/fields/manyToMany');
const ManyToOne     = require('./lib/fields/manyToOne');

const Serializer                    = require('./lib/serializers/serializer')
const ModelSerializer               = require('./lib/serializers/modelSerializer');
const FieldRelatedSerializer        = require('./lib/serializers/fieldRelatedSerializer');
const PrimaryKeyRelatedSerializer   = require('./lib/serializers/primaryKeyRelatedSerializer');

const BaseView      = require('./lib/views/baseView');
const ModelView     = require('./lib/views/modelView');



module.exports = {
  models: {
    BaseModel: BaseModel
  },
  daos: {
    BaseDAO: BaseDAO
  },
  fields: {
    BaseField: BaseField,
    ForeignKey: ForeignKey,
    ManyToMany: ManyToMany,
    ManyToOne: ManyToOne
  },
  serializers: {
    Serializer: Serializer,
    ModelSerializer: ModelSerializer,
    FieldRelatedSerializer: FieldRelatedSerializer,
    PrimaryKeyRelatedSerializer: PrimaryKeyRelatedSerializer
  },
  views: {
    BaseView: BaseView,
    ModelView: ModelView
  }
}
