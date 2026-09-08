import {
  create as admin_create,
  list as admin_list,
  remove as admin_remove,
  update as admin_update,
} from '@/api/address_book_collection';
import {
  create as my_create,
  list as my_list,
  remove as my_remove,
  update as my_update,
} from '@/api/my/address_book_collection';
import { T } from '@/utils/i18n';
import { ElMessage, ElMessageBox } from 'element-plus';
import { reactive, ref } from 'vue';

const apis = {
  admin: { list: admin_list, remove: admin_remove, update: admin_update, create: admin_create },
  my: { list: my_list, remove: my_remove, create: my_create, update: my_update },
};

export function useRepositories(api_type = 'my') {
  const listRes = reactive({
    list: [],
    total: 0,
    loading: false,
  });
  const listQuery = reactive({
    page: 1,
    page_size: 10,
    name: null,
    user_id: null,
  });

  const getList = async () => {
    listRes.loading = true;
    const res = await apis[api_type].list(listQuery).catch((_) => false);
    listRes.loading = false;
    if (res) {
      listRes.list = res.data.list;
      listRes.total = res.data.total;
    }
  };
  const handlerQuery = () => {
    if (listQuery.page === 1) {
      getList();
    } else {
      listQuery.page = 1;
    }
  };

  const del = async (row) => {
    const cf = await ElMessageBox.confirm(T('Confirm?', { param: T('Delete') }), {
      confirmButtonText: T('Confirm'),
      cancelButtonText: T('Cancel'),
      type: 'warning',
    }).catch((_) => false);
    if (!cf) {
      return false;
    }

    const res = await apis[api_type].remove({ id: row.id }).catch((_) => false);
    if (res) {
      ElMessage.success(T('OperationSuccess'));
      getList();
    }
  };

  const formVisible = ref(false);
  const formData = reactive({
    id: 0,
    name: '',
  });

  const toEdit = (row) => {
    formVisible.value = true;
    //Assign the data in row to formData
    Object.keys(formData).forEach((key) => {
      formData[key] = row[key];
    });
  };
  const toAdd = () => {
    formVisible.value = true;
    //Reset formData
    Object.keys(formData).forEach((key) => {
      formData[key] = undefined;
    });
  };
  const submit = async () => {
    const api = formData.id ? apis[api_type].update : apis[api_type].create;
    const res = await api(formData).catch((_) => false);
    if (res) {
      ElMessage.success(T('OperationSuccess'));
      formVisible.value = false;
      getList();
    }
  };
  return {
    listRes,
    listQuery,
    getList,
    handlerQuery,
    del,
    formVisible,
    formData,
    toEdit,
    toAdd,
    submit,
  };
}
